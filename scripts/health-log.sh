#!/usr/bin/env bash
set -euo pipefail
# Opt-in host installation only; default path is written only when invoked.
LOG_FILE=${HEALTH_LOG_FILE:-/var/log/cloudlaunch/health.jsonl}
healthy=0
if curl --connect-timeout 2 --max-time 3 -fsS http://127.0.0.1:3000/health >/dev/null; then healthy=1; fi
printf '{"event":"health_probe","healthy":%s,"timestamp":"%s"}\n' "$healthy" "$(date -u +%FT%TZ)" >> "$LOG_FILE"
# Record a failed probe successfully; the CloudWatch alarm evaluates healthy=0.
