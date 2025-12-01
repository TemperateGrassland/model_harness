output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.region}.amazonaws.com/${var.stage_name}"
}

output "api_key_id" {
  description = "API Gateway API key ID"
  value       = aws_api_gateway_api_key.main.id
}

output "api_key_value" {
  description = "API Gateway API key value"
  value       = aws_api_gateway_api_key.main.value
  sensitive   = true
}

output "generate_endpoint_url" {
  description = "Full URL for the generate endpoint"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.region}.amazonaws.com/${var.stage_name}/generate"
}

output "usage_plan_id" {
  description = "API Gateway usage plan ID"
  value       = aws_api_gateway_usage_plan.main.id
}