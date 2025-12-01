variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "sagemaker_endpoint_name" {
  description = "Name of the SageMaker endpoint to proxy to"
  type        = string
}

variable "stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "prod"
}

variable "api_quota_limit" {
  description = "Daily API quota limit"
  type        = number
  default     = 1000
}

variable "api_rate_limit" {
  description = "API rate limit (requests per second)"
  type        = number
  default     = 10
}

variable "api_burst_limit" {
  description = "API burst limit"
  type        = number
  default     = 20
}