
provider "aws" {
  region = "var.aws_region"
}

resource "aws_ecr_repository" "cloudlaunch" {
  name                 = "cloudlaunch"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Project     = "CloudLaunch"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
