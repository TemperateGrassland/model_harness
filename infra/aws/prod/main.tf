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
  initial_instance_count = 1  # Start with 1 instances and then scale-to-zero. At least 1 must be used. 
  vpc_subnet_ids         = var.vpc_subnet_ids
  vpc_security_group_ids = var.vpc_security_group_ids
  async_s3_output_path   = var.async_s3_output_path
  async_s3_failure_path  = var.async_s3_failure_path
  
  # Auto Scaling Configuration
  min_capacity           = var.min_capacity
  max_capacity           = var.max_capacity
}

# ============================================================================
# PRODUCTION API INFRASTRUCTURE
# ============================================================================

# Application Load Balancer
module "alb_api" {
  count  = var.enable_api_gateway ? 1 : 0
  source = "../../modules/alb_api"

  name_prefix        = var.name_prefix
  vpc_id             = data.aws_vpc.main.id
  public_subnet_ids  = var.public_subnet_ids
  certificate_arn    = var.certificate_arn
}

# ECS API Service  
module "ecs_api" {
  count  = var.enable_api_gateway ? 1 : 0
  source = "../../modules/ecs_api"

  name_prefix              = var.name_prefix
  vpc_id                   = data.aws_vpc.main.id
  private_subnet_ids       = var.vpc_subnet_ids
  target_group_arn         = module.alb_api[0].target_group_arn
  alb_security_group_id    = module.alb_api[0].alb_security_group_id
  image_uri                = var.image_uri
  sagemaker_endpoint_name  = module.sagemaker_endpoint.endpoint_name
  s3_bucket_name           = local.s3_bucket_name
  jwt_secret_key           = var.jwt_secret_key
  redis_host               = var.enable_api_gateway && length(module.redis) > 0 ? module.redis[0].redis_endpoint : ""
  cpu                      = var.api_cpu
  memory                   = var.api_memory

  depends_on = [module.sagemaker_endpoint]
}

# Redis for rate limiting (after ECS so we can reference its security group)
module "redis" {
  count  = var.enable_api_gateway ? 1 : 0
  source = "../../modules/redis"

  name_prefix            = var.name_prefix
  vpc_id                 = data.aws_vpc.main.id
  private_subnet_ids     = var.vpc_subnet_ids
  ecs_security_group_id  = module.ecs_api[0].ecs_security_group_id
  node_type              = var.redis_node_type
}

# Extract bucket name from ARN
locals {
  s3_bucket_name = split(":", var.s3_bucket_arn)[5]
}

# VPC Endpoints for cost optimization (avoid NAT Gateway charges)
data "aws_vpc" "main" {
  filter {
    name   = "vpc-id" 
    values = [data.aws_subnet.first.vpc_id]
  }
}

data "aws_subnet" "first" {
  id = var.vpc_subnet_ids[0]
}

data "aws_route_table" "private" {
  subnet_id = var.vpc_subnet_ids[0]
}

# S3 VPC Endpoint (Gateway endpoint - no cost)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.private.id]

  tags = {
    Name         = "${var.name_prefix}-s3-endpoint"
    ResourceType = "vpc-endpoint"
    Function     = "cost-optimization"
    Service      = "s3"
    EndpointType = "gateway"
  }
}

# VPC Endpoint Security Group (for interface endpoints)
resource "aws_security_group" "vpc_endpoint_sg" {
  name_prefix = "${var.name_prefix}-vpc-endpoint-"
  vpc_id      = data.aws_vpc.main.id
  description = "Security group for VPC endpoints"

  ingress {
    description = "HTTPS from ECS tasks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  tags = {
    Name         = "${var.name_prefix}-vpc-endpoint-sg"
    ResourceType = "security-group"
    Function     = "vpc-endpoints"
  }
}

# ECR API VPC Endpoint (Interface endpoint)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.vpc_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name         = "${var.name_prefix}-ecr-api-endpoint"
    ResourceType = "vpc-endpoint"
    Function     = "ecs-connectivity"
    Service      = "ecr-api"
    EndpointType = "interface"
  }
}

# ECR Docker VPC Endpoint (Interface endpoint)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.vpc_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name         = "${var.name_prefix}-ecr-dkr-endpoint"
    ResourceType = "vpc-endpoint"
    Function     = "ecs-connectivity"
    Service      = "ecr-docker"
    EndpointType = "interface"
  }
}

# CloudWatch Logs VPC Endpoint (for ECS logging)
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.vpc_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name         = "${var.name_prefix}-logs-endpoint"
    ResourceType = "vpc-endpoint"
    Function     = "ecs-logging"
    Service      = "cloudwatch-logs"
    EndpointType = "interface"
  }
}

# SageMaker Runtime VPC Endpoint (Interface endpoint)
resource "aws_vpc_endpoint" "sagemaker_runtime" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.sagemaker.runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.vpc_subnet_ids
  security_group_ids  = var.vpc_security_group_ids
  private_dns_enabled = true

  tags = {
    Name         = "${var.name_prefix}-sagemaker-runtime-endpoint"
    ResourceType = "vpc-endpoint"
    Function     = "cost-optimization"
    Service      = "sagemaker-runtime"
    EndpointType = "interface"
  }
}