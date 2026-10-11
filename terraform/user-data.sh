
#!/bin/bash
set -euxo pipefail

# Update Ubuntu package information
apt-get update -y

# Install Docker and AWS CLI
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io awscli

# Start Docker automatically
systemctl enable --now docker

# Allow the ubuntu user to use Docker
usermod -aG docker ubuntu

# Write a startup completion message
echo "CloudLaunch EC2 bootstrap completed" > /var/log/cloudlaunch-bootstrap.log
