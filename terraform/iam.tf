
# Reference the existing role and instance profile. No IAM resources or policy
# attachments are declared, so Terraform cannot create or alter them.
data "aws_iam_role" "cloudlaunch_ec2" {
  name = "cloudlaunch-ec2-ecr-role"
}

data "aws_iam_instance_profile" "cloudlaunch_ec2" {
  name = "cloudlaunch-ec2-ecr-role"
}
