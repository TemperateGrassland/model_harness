output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.arn
}

output "sagemaker_model_name" {
  description = "Name of the SageMaker model"
  value       = module.sagemaker_endpoint.model_name
}

output "sagemaker_endpoint_config_name" {
  description = "Name of the SageMaker endpoint configuration"
  value       = module.sagemaker_endpoint.endpoint_config_name
}

output "sagemaker_endpoint_name" {
  description = "Name of the SageMaker endpoint"
  value       = module.sagemaker_endpoint.endpoint_name
}

output "sagemaker_endpoint_url" {
  description = "URL for invoking the SageMaker endpoint"
  value       = "https://runtime.sagemaker.${var.region}.amazonaws.com/endpoints/${module.sagemaker_endpoint.endpoint_name}/invocations"
}

# ============================================================================
# API GATEWAY OUTPUTS
# ============================================================================

output "api_endpoint_url" {
  description = "API Gateway endpoint URL"
  value       = var.enable_api_gateway ? "http://${module.alb_api[0].alb_dns_name}" : "API Gateway not enabled"
}

output "api_load_balancer_dns" {
  description = "Load Balancer DNS name for API"
  value       = var.enable_api_gateway ? module.alb_api[0].alb_dns_name : null
}

output "redis_endpoint" {
  description = "Redis endpoint for rate limiting"
  value       = var.enable_api_gateway && length(module.redis) > 0 ? module.redis[0].redis_endpoint : null
  sensitive   = true
}