resource "aws_sagemaker_model" "sync" {
  name               = "${var.name_prefix}-sync-model"
  execution_role_arn = var.execution_role_arn

  primary_container {
    image          = var.image_uri
    model_data_url = var.model_data_url
    mode           = "SingleModel"

    environment = {
      MODEL_DIR         = "/opt/ml/model"
      MODEL_S3_LOCATION = var.model_data_url
    }
  }

  vpc_config {
    subnets            = var.vpc_subnet_ids
    security_group_ids = var.vpc_security_group_ids
  }

  tags = {
    Name         = "${var.name_prefix}-sync-model"
    ResourceType = "sagemaker-model"
    Function     = "ml-inference-sync"
  }
}

resource "aws_sagemaker_endpoint_configuration" "sync" {
  name = "${var.name_prefix}-sync-endpoint-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.sync.name
    initial_instance_count = var.initial_instance_count
    instance_type          = var.instance_type

    # Sync-specific timeouts
    container_startup_health_check_timeout_in_seconds = 600
    model_data_download_timeout_in_seconds           = 600
  }

  # NO async_inference_config block = synchronous endpoint

  tags = {
    Name         = "${var.name_prefix}-sync-endpoint-config"
    ResourceType = "sagemaker-endpoint-config"
    Function     = "ml-inference-sync"
    InstanceType = var.instance_type
  }
}

resource "aws_sagemaker_endpoint" "sync" {
  name                 = "${var.name_prefix}-sync-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.sync.name

  tags = {
    Name         = "${var.name_prefix}-sync-endpoint"
    ResourceType = "sagemaker-endpoint"
    Function     = "ml-inference-sync"
    InstanceType = var.instance_type
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto-scaling for sync endpoint
resource "aws_appautoscaling_target" "sync_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "endpoint/${aws_sagemaker_endpoint.sync.name}/variant/AllTraffic"
  scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
  service_namespace  = "sagemaker"

  depends_on = [aws_sagemaker_endpoint.sync]
}

resource "aws_appautoscaling_policy" "sync_scale_out" {
  name               = "${var.name_prefix}-sync-scale-out"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sync_target.resource_id
  scalable_dimension = aws_appautoscaling_target.sync_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.sync_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.target_invocations_per_instance
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
    }
  }
}