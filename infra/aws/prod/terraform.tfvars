# AWS Configuration
region = "eu-west-1"

# Resource naming
name_prefix = "model-harness"

# Container Configuration
# Update this with your actual ECR URI after building and pushing the image
image_uri = "559972484328.dkr.ecr.eu-west-1.amazonaws.com/model_harness:latest"

# Instance Configuration
instance_type          = "ml.g4dn.xlarge"
initial_instance_count = 1

# VPC Configuration - Set via environment variables for security:
# export TF_VAR_vpc_subnet_ids='["subnet-xxxxxxxx","subnet-yyyyyyyy"]'
# export TF_VAR_vpc_security_group_ids='["sg-xxxxxxxx"]'

# S3 Configuration (update with your actual S3 bucket)
s3_bucket_arn         = "arn:aws:s3:::model-harness-io"
async_s3_output_path  = "s3://model-harness-io/stable_diffusion/outputs/"
async_s3_failure_path = "s3://model-harness-io/stable_diffusion/failures/"