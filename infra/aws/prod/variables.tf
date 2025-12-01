variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "model-harness"
}

variable "image_uri" {
  description = "ECR URI for the Docker image"
  type        = string
}

variable "model_data_url" {
  description = "S3 URL for model artifacts"
  type        = string
}

variable "instance_type" {
  description = "SageMaker instance type"
  type        = string
  default     = "ml.g4dn.xlarge"
}

variable "initial_instance_count" {
  description = "Initial number of instances"
  type        = number
  default     = 1
}

variable "vpc_subnet_ids" {
  description = "List of subnet IDs for VPC configuration"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs for VPC configuration"
  type        = list(string)
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for async inference"
  type        = string
}

variable "async_s3_output_path" {
  description = "S3 path for async inference outputs"
  type        = string
}

variable "async_s3_failure_path" {
  description = "S3 path for failed async inference outputs"
  type        = string
}

# Auto Scaling Configuration (optional overrides)
variable "enable_autoscaling" {
  description = "Enable auto scaling for the SageMaker endpoint"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum number of instances (0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Maximum number of instances"
  type        = number
  default     = 1
}

# ============================================================================
# API GATEWAY VARIABLES
# ============================================================================

variable "enable_api_gateway" {
  description = "Enable API Gateway with ALB and ECS"
  type        = bool
  default     = false
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB (required if enable_api_gateway is true)"
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional)"
  type        = string
  default     = ""
}

variable "jwt_secret_key" {
  description = "JWT secret key for authentication"
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "api_cpu" {
  description = "CPU units for API ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "api_memory" {
  description = "Memory MB for API ECS task"
  type        = number
  default     = 2048
}

# ============================================================================
# SAGEMAKER API GATEWAY VARIABLES
# ============================================================================

variable "enable_sagemaker_api_gateway" {
  description = "Enable API Gateway for direct SageMaker access"
  type        = bool
  default     = false
}

variable "api_stage_name" {
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