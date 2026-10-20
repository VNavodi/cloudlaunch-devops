#!/usr/bin/env bash
set -euo pipefail
REGION=ap-southeast-2
INSTANCE_ID=i-0b469c30aee75c370
ACCOUNT=636621822646
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
TAG="${1:?Usage: scripts/deploy.sh IMAGE_TAG}"
[[ "$TAG" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'ERROR: Invalid image tag' >&2; exit 1; }

for cmd in aws python3 base64; do command -v "$cmd" >/dev/null || { echo "ERROR: Missing $cmd" >&2; exit 1; }; done
DIGEST=$(aws ecr describe-images --repository-name cloudlaunch --image-ids "imageTag=$TAG" \
  --region "$REGION" --query 'imageDetails[0].imageDigest' --output text)
[[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'ERROR: ECR image digest not found' >&2; exit 1; }
IMAGE="$REGISTRY/cloudlaunch@$DIGEST"
echo "Resolved immutable image: $IMAGE"

if [[ "${DEPLOY_ENABLED:-false}" != true ]]; then
  echo 'DRY RUN: DEPLOY_ENABLED is not true. No EC2 changes made.'
  exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROMOTE_B64=$(base64 -w0 "$SCRIPT_DIR/promote-container.sh")
# Interpolate only validated digest and locally generated base64 source.
REMOTE_SCRIPT=$(cat <<REMOTE
#!/usr/bin/env bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION='$REGION'
IMAGE='$IMAGE'
REGISTRY='$REGISTRY'
PROMOTE_B64='$PROMOTE_B64'

# SSM commands on the same instance must not overlap.
exec 9>/var/lock/cloudlaunch-deploy.lock
flock -n 9 || { echo 'ERROR: Another CloudLaunch deployment is in progress' >&2; exit 1; }

[[ "\$(docker inspect cloudlaunch-app --format '{{.State.Status}}')" == running ]] || { echo 'ERROR: Production not running' >&2; exit 1; }
curl -fsS http://127.0.0.1:3000/health >/dev/null
if docker container inspect cloudlaunch-app-previous >/dev/null 2>&1; then
  echo 'ERROR: Existing rollback backup. Resolve before next deployment.' >&2
  exit 1
fi
if docker container inspect cloudlaunch-candidate >/dev/null 2>&1; then
  echo 'ERROR: Candidate already exists' >&2
  exit 1
fi

CURRENT_ID=\$(docker inspect cloudlaunch-app --format '{{.Image}}')
CURRENT_DIGESTS=\$(docker image inspect "\$CURRENT_ID" --format '{{range .RepoDigests}}{{println .}}{{end}}')
if printf '%s\n' "\$CURRENT_DIGESTS" | grep -Fxq "\$IMAGE"; then
  echo 'Target image already deployed; no changes made.'
  exit 0
fi

# Uses EC2 instance IAM role, not stored AWS access keys.
TMP_CONFIG=\$(mktemp -d)
export DOCKER_CONFIG="\$TMP_CONFIG"
PROMOTE_FILE=''
cleanup() {
  docker rm -f cloudlaunch-candidate >/dev/null 2>&1 || true
  if [[ -n "\$PROMOTE_FILE" ]]; then rm -f "\$PROMOTE_FILE"; fi
  rm -rf "\$TMP_CONFIG"
}
trap cleanup EXIT
aws ecr get-login-password --region '$REGION' | docker login --username AWS --password-stdin "\$REGISTRY"
docker pull "\$IMAGE"

echo 'Testing candidate on loopback port 3001...'
docker run -d --name cloudlaunch-candidate --memory=128m --restart=no \
  -p 127.0.0.1:3001:3000 "\$IMAGE"
healthy=0
for attempt in \$(seq 1 15); do
  if curl -fsS http://127.0.0.1:3001/health >/dev/null 2>&1; then healthy=1; break; fi
  sleep 2
done
[[ "\$healthy" == 1 ]] || { echo 'ERROR: Candidate unhealthy; production unchanged' >&2; exit 1; }
docker rm -f cloudlaunch-candidate >/dev/null

echo 'Candidate healthy; starting production promotion...'
PROMOTE_FILE=\$(mktemp)
printf '%s' "\$PROMOTE_B64" | base64 -d > "\$PROMOTE_FILE"
chmod 700 "\$PROMOTE_FILE"
# Keep temp promotion script until it completes; exit trap handles cleanup.
PROMOTION_ENABLED=true bash "\$PROMOTE_FILE" "\$IMAGE"
rm -f "\$PROMOTE_FILE"
echo 'EC2 deployment completed.'
REMOTE
)
PARAMETERS=$(printf '%s' "$REMOTE_SCRIPT" | python3 -c 'import json,sys; print(json.dumps({"commands":[sys.stdin.read()]}))')
COMMAND_ID=$(aws ssm send-command --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --parameters "$PARAMETERS" \
  --timeout-seconds 600 --region "$REGION" \
  --query 'Command.CommandId' --output text)
echo "SSM command ID: $COMMAND_ID"
# Poll until terminal status, including commands that take longer than the AWS CLI waiter window.
for attempt in $(seq 1 120); do
  STATUS=$(aws ssm get-command-invocation --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" --region "$REGION" --query Status --output text 2>/dev/null || true)
  case "$STATUS" in
    Success|Failed|Cancelled|TimedOut|Cancelling|DeliveryTimedOut|ExecutionTimedOut|Undeliverable|Terminated) break ;;
  esac
  sleep 5
done
aws ssm get-command-invocation --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" --region "$REGION" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' --output json
[[ "${STATUS:-}" == Success ]] || { echo "ERROR: SSM deployment ended with status ${STATUS:-unknown}" >&2; exit 1; }
