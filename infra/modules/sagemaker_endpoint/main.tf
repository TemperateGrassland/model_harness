resource "aws_sagemaker_model" "this" {
  name               = "${var.name_prefix}-model"
  execution_role_arn = var.execution_role_arn

  primary_container {
    image          = var.image_uri
    model_data_url = var.model_data_url
    mode           = "SingleModel"

    # Optional, for env to your container (MODEL_DIR, etc.)
    environment = {
      MODEL_DIR = "/opt/ml/model"
    }
  }

  vpc_config {
    subnets         = var.vpc_subnet_ids
    security_group_ids = var.vpc_security_group_ids
  }

  tags = {
    Name         = "${var.name_prefix}-model"
    ResourceType = "sagemaker-model"
    Function     = "ml-inference"
  }
}

resource "aws_sagemaker_endpoint_configuration" "this" {
  name = "${var.name_prefix}-endpoint-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.this.name
    initial_instance_count = var.initial_instance_count
    instance_type          = var.instance_type
  }

  async_inference_config {
    output_config {
      s3_output_path = var.async_s3_output_path

      # Optional: path for failed invocations
      s3_failure_path = var.async_s3_failure_path
    }

    client_config {
      max_concurrent_invocations_per_instance = var.async_max_concurrent_invocations_per_instance
    }
  }

  tags = {
    Name         = "${var.name_prefix}-endpoint-config"
    ResourceType = "sagemaker-endpoint-config"
    Function     = "ml-inference"
    InstanceType = var.instance_type
  }
}

resource "aws_sagemaker_endpoint" "this" {
  name                 = "${var.name_prefix}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.this.name

  tags = {
    Name         = "${var.name_prefix}-endpoint"
    ResourceType = "sagemaker-endpoint"
    Function     = "ml-inference"
    Scaling      = "auto-scale-to-zero"
    InstanceType = var.instance_type
  }
}

# Application Auto Scaling Target
resource "aws_appautoscaling_target" "sagemaker_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "endpoint/${aws_sagemaker_endpoint.this.name}/variant/AllTraffic"
  scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
  service_namespace  = "sagemaker"

  depends_on = [aws_sagemaker_endpoint.this]

  tags = {
    Name         = "${var.name_prefix}-autoscaling-target"
    ResourceType = "autoscaling-target"
    Function     = "cost-optimization"
    MinCapacity  = var.min_capacity
    MaxCapacity  = var.max_capacity
  }
}

# Scale-Out Policy (when invocations increase)
resource "aws_appautoscaling_policy" "sagemaker_scale_out" {
  name               = "${var.name_prefix}-sagemaker-scale-out"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sagemaker_target.resource_id
  scalable_dimension = aws_appautoscaling_target.sagemaker_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.sagemaker_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.target_invocations_per_instance
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
    }
  }
}

# Scale-In Policy (when invocations are low - scale to zero)
resource "aws_appautoscaling_policy" "sagemaker_scale_in" {
  name               = "${var.name_prefix}-sagemaker-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.sagemaker_target.resource_id
  scalable_dimension = aws_appautoscaling_target.sagemaker_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.sagemaker_target.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown               = var.scale_in_cooldown
    metric_aggregation_type = "Average"

    # Scale to exactly 0 instances when no invocations
    step_adjustment {
      scaling_adjustment          = 0  # Scale to zero instances
      metric_interval_upper_bound = 0.0
    }
  }
}

# CloudWatch Alarm for scaling to zero (no invocations)
resource "aws_cloudwatch_metric_alarm" "low_invocations" {
  alarm_name          = "${var.name_prefix}-sagemaker-low-invocations"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.scale_in_evaluation_periods
  metric_name         = "Invocations"
  namespace           = "AWS/SageMaker"
  period              = var.scale_in_period
  statistic           = "Sum"
  threshold           = var.low_invocation_threshold
  alarm_description   = "Scale SageMaker endpoint to zero when no invocations"
  alarm_actions       = [aws_appautoscaling_policy.sagemaker_scale_in.arn]

  dimensions = {
    EndpointName = aws_sagemaker_endpoint.this.name
    VariantName  = "AllTraffic"
  }

  treat_missing_data = "breaching"  # Treat missing data as low usage

  tags = {
    Name         = "${var.name_prefix}-low-invocations-alarm"
    ResourceType = "cloudwatch-alarm"
    Function     = "cost-optimization"
    Purpose      = "scale-to-zero"
    Threshold    = var.low_invocation_threshold
  }
}
