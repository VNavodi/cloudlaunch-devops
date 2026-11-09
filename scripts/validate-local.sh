#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for file in scripts/*.sh tests/*.sh; do bash -n "$file"; done
TEMP_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_TEST_DIR"' EXIT
export LOCK_FILE="$TEMP_TEST_DIR/deploy.lock"
unset PROMOTION_ENABLED ROLLBACK_ENABLED DEPLOY_ENABLED CHECK_ENABLED
for file in tests/test-*.sh; do bash "$file"; done
