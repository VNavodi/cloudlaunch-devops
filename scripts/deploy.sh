#!/usr/bin/env bash
set -euo pipefail

REGION="ap-southeast-2"
INSTANCE_ID="i-0b469c30aee75c370"
ECR_REGISTRY="636621822646.dkr.ecr.ap-southeast-2.amazonaws.com"
IMAGE_TAG="${1:?Usage: ./scripts/deploy.sh IMAGE_TAG}"

if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
  echo "Invalid image tag"
  exit 1
fi

echo "Checking CloudLaunch image: $IMAGE_TAG"

IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name cloudlaunch \
  --image-ids "imageTag=${IMAGE_TAG}" \
  --region "$REGION" \
  --query 'imageDetails[0].imageDigest' \
  --output text)

if [[ -z "$IMAGE_DIGEST" || "$IMAGE_DIGEST" == "None" ]]; then
  echo "ERROR: Image digest not found"
  exit 1
fi

IMAGE="${ECR_REGISTRY}/cloudlaunch@${IMAGE_DIGEST}"

echo "Image verified!"
echo "Deployment target: $INSTANCE_ID"
echo "Immutable image: $IMAGE"
echo "Checking EC2 deployment prerequisites..."

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["set -e","docker inspect cloudlaunch-app --format \"Status={{.State.Status}} Restart={{.HostConfig.RestartPolicy.Name}}\"","if docker container inspect cloudlaunch-app-previous >/dev/null 2>&1; then echo \"ERROR: Previous backup already exists\"; exit 1; fi","curl -fsS http://127.0.0.1:3000/health"]}' \
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

echo "Preflight checks passed. No deployment changes made."


echo "Checking whether target image is already deployed..."

CURRENT_IMAGE_COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters '{"commands":["IMAGE_ID=$(docker inspect cloudlaunch-app --format \"{{.Image}}\")","docker image inspect \"$IMAGE_ID\" --format \"{{range .RepoDigests}}{{println .}}{{end}}\""]}' \
  --region "$REGION" \
  --query 'Command.CommandId' \
  --output text)

aws ssm wait command-executed \
  --command-id "$CURRENT_IMAGE_COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"

CURRENT_REPO_DIGESTS=$(aws ssm get-command-invocation \
  --command-id "$CURRENT_IMAGE_COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'StandardOutputContent' \
  --output text)

if printf '%s\n' "$CURRENT_REPO_DIGESTS" | grep -Fxq "$IMAGE"; then
  echo "Image $IMAGE_TAG is already deployed."
  echo "Skipping candidate test and production deployment."
  exit 0
fi

echo "Starting candidate deployment test..."

REMOTE_SCRIPT=$(cat <<EOF
set -eu

if docker container inspect cloudlaunch-candidate >/dev/null 2>&1; then
  echo "ERROR: Candidate container already exists"
  exit 1
fi

cleanup() {
  docker rm -f cloudlaunch-candidate >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d \
  --name cloudlaunch-candidate \
  --memory=128m \
  --restart=no \
  -p 127.0.0.1:3001:3000 \
  "$IMAGE"

healthy=0
for attempt in \$(seq 1 10); do
  if curl -fsS http://127.0.0.1:3001/health; then
    healthy=1
    break
  fi
  sleep 2
done

if [ "\$healthy" -ne 1 ]; then
  echo "ERROR: Candidate health check failed"
  exit 1
fi

echo
echo "Candidate health check passed"
EOF
)

PARAMETERS=$(printf '%s' "$REMOTE_SCRIPT" | python3 -c \
  'import json,sys; print(json.dumps({"commands":[sys.stdin.read()]}))')

CANDIDATE_COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "$PARAMETERS" \
  --region "$REGION" \
  --query 'Command.CommandId' \
  --output text)

echo "Candidate SSM Command ID: $CANDIDATE_COMMAND_ID"

if aws ssm wait command-executed \
  --command-id "$CANDIDATE_COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"; then
  echo "Candidate SSM execution completed."
else
  echo "ERROR: Candidate SSM execution failed or timed out."
  aws ssm get-command-invocation \
    --command-id "$CANDIDATE_COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
    --output json || true
  exit 1
fi

aws ssm get-command-invocation \
  --command-id "$CANDIDATE_COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json

echo "Candidate test completed. Production unchanged."