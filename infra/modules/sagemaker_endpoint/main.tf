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
}

resource "aws_sagemaker_endpoint" "this" {
  name                 = "${var.name_prefix}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.this.name
}