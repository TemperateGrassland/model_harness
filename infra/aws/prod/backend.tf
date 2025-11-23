terraform {
  backend "s3" {
    bucket         = "model-harness-tf-state-bucket"
    key            = "model-harness/prod/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}