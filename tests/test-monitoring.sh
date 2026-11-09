#!/usr/bin/env bash
set -euo pipefail
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
printf '#!/usr/bin/env bash\nexit "${PROBE_STATUS:-0}"\n' > "$TEST_DIR/curl"
chmod +x "$TEST_DIR/curl"
export PATH="$TEST_DIR:$PATH" HEALTH_LOG_FILE="$TEST_DIR/health.jsonl"
PROBE_STATUS=0 bash scripts/health-log.sh
PROBE_STATUS=1 bash scripts/health-log.sh
node <<'JS'
const fs=require('fs'),assert=require('assert/strict');
const rows=fs.readFileSync(process.env.HEALTH_LOG_FILE,'utf8').trim().split('\n').map(JSON.parse);
assert.deepEqual(rows.map(r=>r.healthy),[1,0]);
assert(rows.every(r=>r.event==='health_probe'));
const cfg=JSON.parse(fs.readFileSync('monitoring/cloudwatch-agent.json'));
assert.equal(cfg.logs.logs_collected.files.collect_list[0].log_group_name,'/cloudlaunch/application');
assert(!cfg.metrics);
JSON.parse(fs.readFileSync('monitoring/ec2-logs-policy.json'));
console.log('PASS: monitoring success/failure events and logs-only agent configuration');
JS
