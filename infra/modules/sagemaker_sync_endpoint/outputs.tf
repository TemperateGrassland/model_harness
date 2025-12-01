output "endpoint_name" {
  description = "Name of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.sync.name
}

output "endpoint_arn" {
  description = "ARN of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.sync.arn
}

output "endpoint_config_name" {
  description = "Name of the endpoint configuration"
  value       = aws_sagemaker_endpoint_configuration.sync.name
}

output "model_name" {
  description = "Name of the SageMaker model"
  value       = aws_sagemaker_model.sync.name
}