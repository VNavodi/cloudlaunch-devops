output "existing_vpc_id" {
  value = data.aws_vpc.default.id
}

output "existing_subnet_id" {
  value = data.aws_subnet.cloudlaunch.id
}

output "existing_security_group_id" {
  value = data.aws_security_group.cloudlaunch.id
}

output "existing_ecr_repository_url" {
  value = data.aws_ecr_repository.cloudlaunch.repository_url
}

output "existing_iam_role_name" {
  value = data.aws_iam_role.cloudlaunch_ec2.name
}

output "existing_instance_profile_name" {
  value = data.aws_iam_instance_profile.cloudlaunch_ec2.name
}

output "existing_ec2_instance_id" {
  value = data.aws_instance.cloudlaunch.id
}

output "existing_ec2_instance_state" {
  value = data.aws_instance.cloudlaunch.instance_state
}
