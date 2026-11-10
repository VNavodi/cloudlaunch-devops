
provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "frontend" {
  name                 = "cloudlaunch-frontend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "cloudlaunch-frontend"
    Project   = "CloudLaunch"
    ManagedBy = "Terraform"
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "cloudlaunch-backend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "cloudlaunch-backend"
    Project   = "CloudLaunch"
    ManagedBy = "Terraform"
  }
}
