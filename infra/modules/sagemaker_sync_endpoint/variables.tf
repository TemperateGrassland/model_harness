variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "image_uri" {
  description = "ECR image URI for the model container"
  type        = string
}

variable "model_data_url" {
  description = "S3 URL for the model data"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN for SageMaker execution"
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

variable "min_capacity" {
  description = "Minimum capacity for auto scaling"
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Maximum capacity for auto scaling"
  type        = number
  default     = 3
}

variable "target_invocations_per_instance" {
  description = "Target invocations per instance for scaling"
  type        = number
  default     = 10
}

variable "scale_in_cooldown" {
  description = "Scale in cooldown period in seconds"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Scale out cooldown period in seconds"
  type        = number
  default     = 60
}

variable "vpc_subnet_ids" {
  description = "List of VPC subnet IDs"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs"
  type        = list(string)
}