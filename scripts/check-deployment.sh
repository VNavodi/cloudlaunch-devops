#!/usr/bin/env bash
set -euo pipefail

REGION="ap-southeast-2"
INSTANCE_ID="i-0b469c30aee75c370"

echo "Checking CloudLaunch EC2 deployment..."

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["docker ps --filter name=^/cloudlaunch-app$","curl -fsS http://127.0.0.1:3000/health"]}' \
  --region "$REGION" \
  --query 'Command.CommandId' \
  --output text)

echo "SSM Command ID: $COMMAND_ID"

aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json

echo "CloudLaunch deployment check completed!"
