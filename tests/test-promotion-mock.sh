
#!/usr/bin/env bash
set -euo pipefail

MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

cat > "$MOCK_DIR/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_LOG"

case "${1:-}" in
  inspect)
    case "$*" in
      *State.Status*) echo running ;;
      *RestartPolicy.Name*) echo unless-stopped ;;
      *PortBindings*) echo 127.0.0.1:3000 ;;
      *) echo mock-container-id ;;
    esac
    ;;
  container)
    exit 1
    ;;
  image)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

cat > "$MOCK_DIR/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$MOCK_DIR/docker" "$MOCK_DIR/curl"

export MOCK_LOG="$MOCK_DIR/docker.log"
export PATH="$MOCK_DIR:$PATH"

IMAGE="636621822646.dkr.ecr.ap-southeast-2.amazonaws.com/cloudlaunch@sha256:c8536f51ae7d4c519ec280cab315043d097f2f903e9c2fc161d77bc6920062b0"

PROMOTION_ENABLED=true \
  ./scripts/promote-container.sh "$IMAGE"

echo
echo "Mock Docker commands executed:"
cat "$MOCK_LOG"

echo
echo "Verifying successful promotion commands..."

if grep -Fq "rename cloudlaunch-app cloudlaunch-app-previous" "$MOCK_LOG" &&
   grep -Fq "run -d --name cloudlaunch-app" "$MOCK_LOG"; then
  echo "PASS: Production backup and replacement commands executed"
else
  echo "FAIL: Expected promotion commands missing"
  exit 1
fi
