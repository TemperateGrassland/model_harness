# AWS Configuration
region = "eu-west-1"

# Resource naming
name_prefix = "model-harness"

# Container Configuration
image_uri = "559972484328.dkr.ecr.eu-west-1.amazonaws.com/model_harness:latest"

# Model Configuration - Set via environment variable for security:
# export TF_VAR_model_data_url="s3://your-bucket/path/to/model.tar.gz"

# Instance Configuration
instance_type          = "ml.g4dn.xlarge"
initial_instance_count = 1

# VPC Configuration - Set via environment variables for security:
# export TF_VAR_vpc_subnet_ids='["subnet-xxxxxxxx","subnet-yyyyyyyy"]'
# export TF_VAR_vpc_security_group_ids='["sg-xxxxxxxx"]'

# S3 Configuration - Set via environment variables for security:
# export TF_VAR_s3_bucket_arn="arn:aws:s3:::your-bucket"
# export TF_VAR_async_s3_output_path="s3://your-bucket/outputs/"
# export TF_VAR_async_s3_failure_path="s3://your-bucket/failures/"