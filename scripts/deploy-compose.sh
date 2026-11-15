#!/usr/bin/env bash
set -euo pipefail

# CloudLaunch Docker Compose deployment preflight.
# This version performs read-only checks only.
# No deployment commands are implemented yet.

REGION="ap-southeast-2"
ACCOUNT="636621822646"
TAG="${1:?Usage: scripts/deploy-compose.sh IMAGE_TAG}"

BACKEND_REPO="cloudlaunch-backend"
FRONTEND_REPO="cloudlaunch-frontend"
COMPOSE_FILE="app/docker-compose.prod.yml"

if [[ ! "$TAG" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "ERROR: Invalid image tag."
    exit 1
fi

for cmd in aws docker; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: Missing required command: $cmd"
        exit 1
    }
done

echo "===== CloudLaunch Compose Preflight ====="

echo "Checking AWS account..."
IDENTITY=$(aws sts get-caller-identity \
    --query Account --output text \
    --region "$REGION")

[[ "$IDENTITY" == "$ACCOUNT" ]] || {
    echo "ERROR: Unexpected AWS account."
    exit 1
}

echo "AWS account verified: $IDENTITY"

echo "Validating production Compose file..."
IMAGE_TAG="$TAG" docker compose \
    -f "$COMPOSE_FILE" config --quiet

echo "Compose configuration is valid."

for REPO in "$BACKEND_REPO" "$FRONTEND_REPO"; do
    echo "Checking ECR image: $REPO:$TAG"

    DIGEST=$(aws ecr describe-images \
        --repository-name "$REPO" \
        --image-ids "imageTag=$TAG" \
        --region "$REGION" \
        --query 'imageDetails[0].imageDigest' \
        --output text)

    [[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || {
        echo "ERROR: Image tag not found or digest invalid: $REPO:$TAG"
        exit 1
    }

    echo "$REPO image verified: $DIGEST"
done

if [[ "${DEPLOY_ENABLED:-false}" != true ]]; then
    echo "DRY RUN: Preflight checks passed."
    echo "No SSM commands sent. No images pulled. No containers changed."
    exit 0
fi

echo "ERROR: Deployment stage has not been implemented yet."
echo "This script is currently preflight-only."
exit 1
