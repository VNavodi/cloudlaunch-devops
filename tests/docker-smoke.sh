#!/usr/bin/env bash
# Explicit local/CI Docker test; not part of credential-free mock runner.
set -euo pipefail
IMAGE=${1:-cloudlaunch:ci}
CONTAINER_ID=''
cleanup() {
  if [[ -n "$CONTAINER_ID" ]]; then docker rm -f "$CONTAINER_ID" >/dev/null; fi
}
trap cleanup EXIT
# Generated ID avoids touching existing production or user container names.
CONTAINER_ID=$(docker run -d --network none "$IMAGE")
ready=0
for _ in $(seq 1 15); do
  if docker exec "$CONTAINER_ID" node -e 'if(process.getuid()===0)process.exit(1);fetch("http://127.0.0.1:3000/health").then(async r=>{if(!r.ok||(await r.json()).status!=="healthy")process.exit(1)}).catch(()=>process.exit(1))'; then
    ready=1; break
  fi
  sleep 1
done
[[ "$ready" == 1 ]] || { docker logs "$CONTAINER_ID"; exit 1; }
docker stop --timeout 10 "$CONTAINER_ID" >/dev/null
[[ $(docker inspect "$CONTAINER_ID" --format '{{.State.ExitCode}}') == 0 ]]
docker logs "$CONTAINER_ID" | grep -F 'CloudLaunch shutting down: SIGTERM'
echo 'PASS: isolated non-root startup, health and graceful shutdown'
