#!/usr/bin/env bash
set -euo pipefail
ROOT=$(pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
for tool in docker curl sleep; do
  printf '#!/usr/bin/env bash\nexec node "%s/tests/fixtures/container-runtime.cjs" %s "$@"\n' "$ROOT" "$tool" > "$TEST_DIR/$tool"
  chmod +x "$TEST_DIR/$tool"
done
export PATH="$TEST_DIR:$PATH" MOCK_STATE="$TEST_DIR/state.json" MOCK_LOG="$TEST_DIR/log" LOCK_FILE="$TEST_DIR/lock"
reset_state() {
  unset UNHEALTHY_OLD FAIL_START SIGNAL_STOP FAIL_RUN
  printf '%s' '{"cloudlaunch-app":{"image":"new","status":"running"},"cloudlaunch-app-previous":{"image":"old","status":"exited"}}' > "$MOCK_STATE"
  : > "$MOCK_LOG"
}
assert_state() { node -e 'const s=require(process.env.MOCK_STATE); const [name,image,status]=process.argv.slice(1); if(!s[name]||s[name].image!==image||s[name].status!==status)process.exit(1)' "$@"; }
reset_state
ROLLBACK_ENABLED=true bash scripts/rollback-container.sh
assert_state cloudlaunch-app old running
assert_state cloudlaunch-app-failed new exited
echo 'PASS: rollback success preserves diagnostic container'
for scenario in UNHEALTHY_OLD FAIL_START SIGNAL_STOP; do
  reset_state
  export "$scenario=true"
  if ROLLBACK_ENABLED=true bash scripts/rollback-container.sh; then echo "FAIL: $scenario accepted"; exit 1; fi
  assert_state cloudlaunch-app new running
  assert_state cloudlaunch-app-previous old exited
  echo "PASS: $scenario fails and recovers original healthy production"
done
reset_state
node -e 'const fs=require("fs"),s=require(process.env.MOCK_STATE);delete s["cloudlaunch-app-previous"];fs.writeFileSync(process.env.MOCK_STATE,JSON.stringify(s))'
if ROLLBACK_ENABLED=true bash scripts/rollback-container.sh; then exit 1; fi
assert_state cloudlaunch-app new running
echo 'PASS: missing backup leaves production intact'
reset_state
exec 8>"$LOCK_FILE"
flock -n 8
if ROLLBACK_ENABLED=true bash scripts/rollback-container.sh; then exit 1; fi
[[ ! -s "$MOCK_LOG" ]]
flock -u 8
exec 8>&-
echo 'PASS: lock contention prevents all Docker operations'
reset_state
ROLLBACK_ENABLED=true bash scripts/rollback-container.sh
if ROLLBACK_ENABLED=true bash scripts/rollback-container.sh; then exit 1; fi
assert_state cloudlaunch-app old running
echo 'PASS: repeated rollback rejected without changing recovered production'
# Exercise promotion with real name/state transitions, including retained failures.
IMAGE=636621822646.dkr.ecr.ap-southeast-2.amazonaws.com/cloudlaunch@sha256:0000000000000000000000000000000000000000000000000000000000000000
reset_promotion() {
  reset_state
  unset UNHEALTHY_NEW
  printf '%s' '{"cloudlaunch-app":{"image":"old","status":"running"}}' > "$MOCK_STATE"
}
reset_promotion
PROMOTION_ENABLED=true bash scripts/promote-container.sh "$IMAGE"
assert_state cloudlaunch-app new running
assert_state cloudlaunch-app-previous old exited
if PROMOTION_ENABLED=true bash scripts/promote-container.sh "$IMAGE"; then exit 1; fi
assert_state cloudlaunch-app new running
echo 'PASS: successful promotion and repeated request preserves backup'
for scenario in FAIL_RUN UNHEALTHY_NEW SIGNAL_STOP; do
  reset_promotion
  export "$scenario=true"
  if PROMOTION_ENABLED=true bash scripts/promote-container.sh "$IMAGE"; then exit 1; fi
  assert_state cloudlaunch-app old running
  if [[ "$scenario" == UNHEALTHY_NEW ]]; then
    node -e 'const s=require(process.env.MOCK_STATE);if(!Object.entries(s).some(([k,v])=>k.startsWith("cloudlaunch-app-failed-")&&v.image==="new"&&v.status==="exited"))process.exit(1)'
  fi
  echo "PASS: promotion $scenario returns failure and recovers original production"
done
