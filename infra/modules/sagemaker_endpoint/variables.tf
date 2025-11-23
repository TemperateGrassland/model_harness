variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  type        = string
}

variable "image_uri" {
  description = "ECR URI for the Docker image"
  type        = string
}

variable "model_data_url" {
  description = "S3 URL for model artifacts (optional for custom containers)"
  type        = string
  default     = null
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

variable "async_s3_output_path" {
  description = "S3 path for async inference outputs"
  type        = string
}

variable "async_s3_failure_path" {
  description = "S3 path for failed async inference outputs"
  type        = string
  default     = null
}

variable "async_max_concurrent_invocations_per_instance" {
  description = "Maximum concurrent invocations per instance for async inference"
  type        = number
  default     = 4
}