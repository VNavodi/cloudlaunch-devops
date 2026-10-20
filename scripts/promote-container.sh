#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: promote-container.sh IMAGE_DIGEST_URI}"

if [[ ! "$IMAGE" =~ ^636621822646\.dkr\.ecr\.ap-southeast-2\.amazonaws\.com/cloudlaunch@sha256:[a-f0-9]{64}$ ]]; then
  echo "ERROR: Invalid CloudLaunch image digest URI"
  exit 1
fi

if [[ "${PROMOTION_ENABLED:-false}" != "true" ]]; then
  echo "DRY RUN: Production promotion is disabled."
  echo "Target image: $IMAGE"
  exit 0
fi

echo "Checking production deployment prerequisites..."

STATUS=$(docker inspect cloudlaunch-app --format '{{.State.Status}}')
RESTART=$(docker inspect cloudlaunch-app --format '{{.HostConfig.RestartPolicy.Name}}')
PORT=$(docker inspect cloudlaunch-app \
  --format '{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostIp}}:{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostPort}}')

if [[ "$STATUS" != "running" ||
      "$RESTART" != "unless-stopped" ||
      "$PORT" != "127.0.0.1:3000" ]]; then
  echo "ERROR: Unexpected production container configuration"
  exit 1
fi

echo "Production configuration verified."

if docker container inspect cloudlaunch-app-previous >/dev/null 2>&1; then
  echo "ERROR: Existing rollback backup detected."
  exit 1
fi

if docker container inspect cloudlaunch-candidate >/dev/null 2>&1; then
  echo "ERROR: Candidate container still exists."
  exit 1
fi

curl -fsS http://127.0.0.1:3000/health

echo
echo "Promotion prerequisites passed."
echo "Target image: $IMAGE"
echo "PREPARATION ONLY: No production changes made."
