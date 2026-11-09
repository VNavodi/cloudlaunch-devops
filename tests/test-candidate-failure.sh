#!/usr/bin/env bash
set -euo pipefail
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export CAPTURE="$TEST_DIR/parameters" AWS_PROFILE=cloudlaunch MOCK_LOG="$TEST_DIR/docker.log"
cat > "$TEST_DIR/aws" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
 *'sts get-caller-identity'*'--query Account'*) echo 636621822646 ;;
 *'sts get-caller-identity'*'--query Arn'*) echo arn:aws:sts::636621822646:assumed-role/test/session ;;
 *'ecr describe-images'*) printf 'sha256:%064d\n' 0 ;;
 *'ssm send-command'*)
  while [[ $# -gt 0 ]]; do if [[ "$1" == --parameters ]]; then printf '%s' "$2" > "$CAPTURE"; break; fi; shift; done
  echo mock-command ;;
 *'ssm get-command-invocation'*) echo "${MOCK_SSM_STATUS:-Success}" ;;
 *'ecr get-login-password'*) echo mock-password ;;
 *) exit 1 ;;
esac
MOCK
# Emulates only the serialization helper, without requiring a Python environment.
cat > "$TEST_DIR/python3" <<'MOCK'
#!/usr/bin/env bash
node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>console.log(JSON.stringify({executionTimeout:["600"],commands:["printf %s "+s+" | base64 -d | bash"]})))'
MOCK
cat > "$TEST_DIR/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$1" in
 inspect) if [[ "$*" == *State.Status* ]]; then echo running; else echo current-id; fi ;;
 container) exit 1 ;;
 image) echo old-image ;;
 login) cat >/dev/null ;;
 pull|run|rm) exit 0 ;;
 *) echo 'Unexpected production mutation' >&2; exit 91 ;;
esac
MOCK
cat > "$TEST_DIR/curl" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" != *':3001/'* ]]
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/sleep"
chmod +x "$TEST_DIR/"{aws,python3,docker,curl,sleep}
export PATH="$TEST_DIR:$PATH"
DEPLOY_ENABLED=true bash scripts/deploy.sh sha-test
if MOCK_SSM_STATUS=Failed DEPLOY_ENABLED=true bash scripts/deploy.sh sha-test; then
  echo 'FAIL: failed SSM invocation reported success'; exit 1
fi
echo 'PASS: failed SSM invocation returns non-zero'
node -e 'const fs=require("fs"),p=JSON.parse(fs.readFileSync(process.env.CAPTURE));if(p.executionTimeout[0]!=="600")process.exit(1);const b=p.commands[0].split(" ")[2];fs.writeFileSync(process.argv[1],Buffer.from(b,"base64"))' "$TEST_DIR/remote.sh"
# Substitute only the host lock location for isolation.
sed -i "s|/var/lock/cloudlaunch-deploy.lock|$TEST_DIR/lock|" "$TEST_DIR/remote.sh"
bash -n "$TEST_DIR/remote.sh"
if bash "$TEST_DIR/remote.sh"; then echo 'FAIL: unhealthy candidate accepted'; exit 1; fi
! grep -Eq '^(stop|rename|update) ' "$MOCK_LOG"
grep -q 'rm -f cloudlaunch-candidate' "$MOCK_LOG"
echo 'PASS: actual generated remote script rejects unhealthy candidate and leaves production unchanged'
