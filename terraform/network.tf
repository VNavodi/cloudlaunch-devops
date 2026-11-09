# Reference the existing AWS VPC
data "aws_vpc" "default" {
  id = "vpc-0e0f77772204fa83a"
}

# Reference the existing EC2 subnet
data "aws_subnet" "cloudlaunch" {
  id = "subnet-0d9c5117cbc3fcfed"
}

# Reference the existing security group
data "aws_security_group" "cloudlaunch" {
  id = "sg-06f33ab5e91c2ad79"
}