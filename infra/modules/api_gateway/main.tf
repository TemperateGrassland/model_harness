# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.name_prefix}-api"
  description = "API Gateway for SageMaker inference with API key authentication"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name         = "${var.name_prefix}-api-gateway"
    ResourceType = "api-gateway"
    Function     = "ml-inference-proxy"
  }
}

# API Gateway Resource (/generate)
resource "aws_api_gateway_resource" "generate" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "generate"
}

# API Gateway Method (POST /generate)
resource "aws_api_gateway_method" "generate_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.generate.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true

  request_models = {
    "application/json" = "Empty"
  }
}

# IAM role for API Gateway to invoke SageMaker
resource "aws_iam_role" "api_gateway_sagemaker_role" {
  name = "${var.name_prefix}-api-gateway-sagemaker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name         = "${var.name_prefix}-api-gateway-sagemaker-role"
    ResourceType = "iam-role"
    Function     = "api-gateway-sagemaker-integration"
  }
}

# Policy for API Gateway to invoke SageMaker
resource "aws_iam_role_policy" "api_gateway_sagemaker_policy" {
  name = "${var.name_prefix}-api-gateway-sagemaker-policy"
  role = aws_iam_role.api_gateway_sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:InvokeEndpoint"
        ]
        Resource = "arn:aws:sagemaker:${var.region}:*:endpoint/${var.sagemaker_endpoint_name}"
      }
    ]
  })
}

# API Gateway Integration with SageMaker
resource "aws_api_gateway_integration" "sagemaker_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method

  integration_http_method = "POST"
  type                   = "AWS"
  uri                    = "arn:aws:apigateway:${var.region}:sagemaker:path/endpoints/${var.sagemaker_endpoint_name}/invocations"
  credentials            = aws_iam_role.api_gateway_sagemaker_role.arn

  # Transform request to SageMaker format
  request_templates = {
    "application/json" = jsonencode({
      prompt = "$input.json('$.prompt')"
    })
  }

  depends_on = [aws_iam_role_policy.api_gateway_sagemaker_policy]
}

# API Gateway Method Response
resource "aws_api_gateway_method_response" "generate_response" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Content-Type" = false
  }
}

# API Gateway Integration Response
resource "aws_api_gateway_integration_response" "sagemaker_response" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method
  status_code = aws_api_gateway_method_response.generate_response.status_code

  response_templates = {
    "application/json" = ""
  }

  depends_on = [aws_api_gateway_integration.sagemaker_integration]
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "main" {
  name        = "${var.name_prefix}-usage-plan"
  description = "Usage plan for SageMaker inference API"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_deployment.main.stage_name
  }

  quota_settings {
    limit  = var.api_quota_limit
    period = "DAY"
  }

  throttle_settings {
    rate_limit  = var.api_rate_limit
    burst_limit = var.api_burst_limit
  }

  depends_on = [aws_api_gateway_deployment.main]
}

# API Key
resource "aws_api_gateway_api_key" "main" {
  name        = "${var.name_prefix}-api-key"
  description = "API key for SageMaker inference API"
  enabled     = true

  tags = {
    Name         = "${var.name_prefix}-api-key"
    ResourceType = "api-key"
    Function     = "ml-inference-auth"
  }
}

# Associate API Key with Usage Plan
resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.main.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main.id
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_method.generate_post,
    aws_api_gateway_integration.sagemaker_integration,
    aws_api_gateway_integration_response.sagemaker_response,
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = var.stage_name

  lifecycle {
    create_before_destroy = true
  }

  # Force redeployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.generate.id,
      aws_api_gateway_method.generate_post.id,
      aws_api_gateway_integration.sagemaker_integration.id,
      aws_api_gateway_integration_response.sagemaker_response.id,
    ]))
  }
}