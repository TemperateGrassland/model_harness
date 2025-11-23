# IAM role for SageMaker execution
resource "aws_iam_role" "sagemaker_execution_role" {
  name = "${var.name_prefix}-sagemaker-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the SageMaker execution policy
resource "aws_iam_role_policy_attachment" "sagemaker_execution_policy" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Additional policy for ECR access
resource "aws_iam_role_policy" "ecr_access" {
  name = "${var.name_prefix}-ecr-access"
  role = aws_iam_role.sagemaker_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# Additional policy for S3 access (for async inference)
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.name_prefix}-s3-access"
  role = aws_iam_role.sagemaker_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arn
      }
    ]
  })
}

module "sagemaker_endpoint" {
  source = "../../modules/sagemaker_endpoint"

  name_prefix            = var.name_prefix
  execution_role_arn     = aws_iam_role.sagemaker_execution_role.arn
  image_uri              = var.image_uri
  model_data_url         = var.model_data_url
  instance_type          = var.instance_type
  initial_instance_count = 0  # Start with 0 instances for scale-to-zero
  vpc_subnet_ids         = var.vpc_subnet_ids
  vpc_security_group_ids = var.vpc_security_group_ids
  async_s3_output_path   = var.async_s3_output_path
  async_s3_failure_path  = var.async_s3_failure_path
  
  # Auto Scaling Configuration
  min_capacity           = var.min_capacity
  max_capacity           = var.max_capacity
}