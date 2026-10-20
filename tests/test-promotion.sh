#!/usr/bin/env bash
set -euo pipefail

echo "CloudLaunch promotion safety tests"

bash -n scripts/promote-container.sh
bash -n scripts/rollback-container.sh
bash -n scripts/deploy.sh

echo "PASS: All deployment scripts have valid Bash syntax"

if ./scripts/promote-container.sh invalid-image >/dev/null 2>&1; then
  echo "FAIL: Invalid image was accepted"
  exit 1
fi

echo "PASS: Invalid image rejected"

OUTPUT=$(./scripts/rollback-container.sh)

if [[ "$OUTPUT" != *"Production rollback is disabled"* ]]; then
  echo "FAIL: Rollback safety guard missing"
  exit 1
fi


echo "PASS: Rollback disabled by default"

if PROMOTION_ENABLED=false \
  ./scripts/promote-container.sh \
  636621822646.dkr.ecr.ap-southeast-2.amazonaws.com/cloudlaunch@sha256:c8536f51ae7d4c519ec280cab315043d097f2f903e9c2fc161d77bc6920062b0 \
  >/dev/null; then
  echo "PASS: Production promotion disabled by default"
else
  echo "FAIL: Promotion dry-run failed"
  exit 1
fi

if ROLLBACK_ENABLED=false \
  ./scripts/rollback-container.sh >/dev/null; then
  echo "PASS: Explicit rollback disable flag works"
else
  echo "FAIL: Rollback disable flag failed"
  exit 1
fi
echo "All initial safety tests passed."
