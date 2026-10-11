
variable "aws_region" {
  description = "AWS region for CloudLaunch"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Project resource naming prefix"
  type        = string
  default     = "cloudlaunch"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
