terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = "ap-southeast-2"
  allowed_account_ids = ["636621822646"]
}

resource "aws_ecr_repository" "cloudlaunch" {
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.ownership_review_approved
      error_message = "Legacy root disabled: review existing state and import ownership before approval."
    }
  }
  name                 = "cloudlaunch"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Project   = "CloudLaunch"
    ManagedBy = "Terraform"
  }
}

variable "ownership_review_approved" {
  type        = bool
  default     = false
  description = "Only enable after explicit ownership/import review and approval; never in validation CI."
}
