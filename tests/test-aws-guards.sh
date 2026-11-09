#!/usr/bin/env bash
set -euo pipefail
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/aws" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_CALL_LOG"
[[ "$*" == *'--profile cloudlaunch'* ]] || exit 1
case "$*" in
  *'sts get-caller-identity'*'--query Account'*) echo "${MOCK_ACCOUNT:-599915810877}" ;;
  *'sts get-caller-identity'*'--query Arn'*) echo arn:aws:iam::636621822646:root ;;
  *) exit 90 ;;
esac
MOCK
chmod +x "$TEST_DIR/aws"
export PATH="$TEST_DIR:$PATH" AWS_CALL_LOG="$TEST_DIR/calls" AWS_PROFILE=cloudlaunch
: > "$AWS_CALL_LOG"
DEPLOY_ENABLED=false bash scripts/deploy.sh sha-test
ROLLBACK_ENABLED=false bash scripts/rollback.sh
CHECK_ENABLED=false bash scripts/check-deployment.sh
[[ ! -s "$AWS_CALL_LOG" ]]
echo 'PASS: default previews make no AWS calls'
for tag in '-bad' 'bad;command' ''; do
  if bash scripts/deploy.sh "$tag" >/dev/null 2>&1; then exit 1; fi
done
for script in deploy rollback check-deployment; do
  : > "$AWS_CALL_LOG"
  if DEPLOY_ENABLED=true ROLLBACK_ENABLED=true CHECK_ENABLED=true bash "scripts/$script.sh" v1; then exit 1; fi
  [[ $(wc -l < "$AWS_CALL_LOG") == 1 ]]
  grep -q 'sts get-caller-identity' "$AWS_CALL_LOG"
done
echo 'PASS: personal account blocked before any ECR/SSM operation'
export MOCK_ACCOUNT=636621822646
if DEPLOY_ENABLED=true bash scripts/deploy.sh v1; then exit 1; fi
! grep -Eq 'ecr|ssm' "$AWS_CALL_LOG"
echo 'PASS: root credentials rejected'
