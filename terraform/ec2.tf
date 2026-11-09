
# Reference the existing EC2 instance. This configuration deliberately does
# not manage its lifecycle, networking, storage, user data, or power state.
data "aws_instance" "cloudlaunch" {
  instance_id = "i-0b469c30aee75c370"
}
