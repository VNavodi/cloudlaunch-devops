#!/usr/bin/env bash
set -Eeuo pipefail

REGION=ap-southeast-2
INSTANCE_ID=i-0b469c30aee75c370
ACCOUNT=636621822646

if [[ "${ROLLBACK_ENABLED:-false}" != true ]]; then
  echo 'DRY RUN: Rollback not authorized. No AWS commands sent.'
  exit 0
fi

for cmd in aws python3 base64; do
  command -v "$cmd" >/dev/null || {
    echo "ERROR: Missing $cmd" >&2
    exit 1
  }
done

IDENTITY=$(aws sts get-caller-identity \
  --query Account --output text)

[[ "$IDENTITY" == "$ACCOUNT" ]] || {
  echo 'ERROR: Unexpected AWS account.' >&2
  exit 1
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROLLBACK_B64=$(base64 -w0 "$SCRIPT_DIR/rollback-container.sh")

REMOTE_SCRIPT=$(cat <<REMOTE
#!/usr/bin/env bash
set -Eeuo pipefail

ROLLBACK_FILE=\$(mktemp)
cleanup() {
  rm -f "\$ROLLBACK_FILE"
}
trap cleanup EXIT

printf '%s' '$ROLLBACK_B64' | base64 -d > "\$ROLLBACK_FILE"
chmod 700 "\$ROLLBACK_FILE"

# The rollback script acquires the shared deployment lock itself.
ROLLBACK_ENABLED=true bash "\$ROLLBACK_FILE"
REMOTE
)

PARAMETERS=$(printf '%s' "$REMOTE_SCRIPT" |
  python3 -c 'import json,sys; print(json.dumps({"commands":[sys.stdin.read()]}))')

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "$PARAMETERS" \
  --timeout-seconds 600 \
  --region "$REGION" \
  --query 'Command.CommandId' \
  --output text)

echo "Rollback SSM command ID: $COMMAND_ID"

STATUS=""
for attempt in $(seq 1 120); do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query Status \
    --output text 2>/dev/null || true)

  case "$STATUS" in
    Success|Failed|Cancelled|TimedOut|Cancelling|DeliveryTimedOut|ExecutionTimedOut|Undeliverable|Terminated)
      break
      ;;
  esac

  sleep 5
done

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json

[[ "$STATUS" == Success ]] || {
  echo "ERROR: Rollback SSM status: ${STATUS:-unknown}" >&2
  exit 1
}
