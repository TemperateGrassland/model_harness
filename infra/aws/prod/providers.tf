terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "ai-infrastructure-engineer-technical-test"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = "model-harness"
      CostCenter  = "ml-inference"
      Component   = "sagemaker-endpoint"
    }
  }
}

