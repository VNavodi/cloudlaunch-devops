provider "aws" {
  region = var.aws_region
}

# Reference the existing ECR repository.
# Terraform will not create or modify this repository.
data "aws_ecr_repository" "cloudlaunch" {
  name = "cloudlaunch"
}