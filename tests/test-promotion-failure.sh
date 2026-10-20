
#!/usr/bin/env bash
set -euo pipefail

# Create a temporary directory for mock commands
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# Mock Docker executable
cat > "$MOCK_DIR/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_LOG"

case "${1:-}" in
  inspect)
    case "$*" in
      *State.Status*)
        echo running
        ;;
      *RestartPolicy.Name*)
        echo unless-stopped
        ;;
      *PortBindings*)
        echo 127.0.0.1:3000
        ;;
      *)
        echo mock-container-id
        ;;
    esac
    ;;

    container)
    case "$*" in
      *"cloudlaunch-app-previous"*)
        if grep -Fq "rename cloudlaunch-app cloudlaunch-app-previous" "$MOCK_LOG"; then
          echo mock-backup-container-id
          exit 0
        fi
        ;;
    esac
    exit 1
    ;;

  image)
    # Simulate target image being available
    exit 0
    ;;

  run)
    # Simulate new production container startup failure
    echo "MOCK ERROR: New production container failed to start" >&2
    exit 1
    ;;

  *)
    # Simulate successful Docker operations
    exit 0
    ;;
esac
EOF

# Mock curl executable
cat > "$MOCK_DIR/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$MOCK_DIR/docker" "$MOCK_DIR/curl"

# Override Docker and curl for this test only
export MOCK_LOG="$MOCK_DIR/docker.log"
export PATH="$MOCK_DIR:$PATH"

IMAGE="636621822646.dkr.ecr.ap-southeast-2.amazonaws.com/cloudlaunch@sha256:c8536f51ae7d4c519ec280cab315043d097f2f903e9c2fc161d77bc6920062b0"

echo "Starting CloudLaunch promotion failure test..."
echo

# Promotion must fail because mock Docker run fails
if PROMOTION_ENABLED=true \
  ./scripts/promote-container.sh "$IMAGE"; then

  echo "FAIL: Promotion unexpectedly succeeded"
  exit 1

else
  echo "PASS: Failed promotion returned non-zero exit status"
fi

echo
echo "Mock Docker commands executed:"
cat "$MOCK_LOG"

echo
echo "Verifying automatic rollback commands..."

if grep -Fq "rename cloudlaunch-app-previous cloudlaunch-app" "$MOCK_LOG" &&
   grep -Fq "start cloudlaunch-app" "$MOCK_LOG"; then

  echo "PASS: Automatic rollback commands were attempted"

else
  echo "FAIL: Automatic rollback commands missing"
  exit 1
fi

echo
echo "CloudLaunch promotion failure test passed."
