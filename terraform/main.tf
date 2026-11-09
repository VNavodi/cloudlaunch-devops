provider "aws" {
  region              = var.aws_region
  allowed_account_ids = ["636621822646"]
}

# Reference the existing ECR repository.
# Terraform will not create or modify this repository.
data "aws_ecr_repository" "cloudlaunch" {
  name = "cloudlaunch"
}
