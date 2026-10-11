
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "cloudlaunch" {
  name_prefix = "${var.project_name}-api-"
  description = "Security group for CloudLaunch API"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow CloudLaunch API traffic"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.project_name}-api-sg"
    Project   = "CloudLaunch"
    ManagedBy = "Terraform"
  }
}
