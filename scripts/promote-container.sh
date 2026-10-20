#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:?Usage: promote-container.sh IMAGE_DIGEST_URI}"
if [[ ! "$IMAGE" =~ ^636621822646\.dkr\.ecr\.ap-southeast-2\.amazonaws\.com/cloudlaunch@sha256:[a-f0-9]{64}$ ]]; then
  echo 'ERROR: Invalid CloudLaunch image digest URI' >&2
  exit 1
fi
if [[ "${PROMOTION_ENABLED:-false}" != true ]]; then
  echo 'DRY RUN: Production promotion is disabled.'
  echo "Target image: $IMAGE"
  exit 0
fi

# Run on the EC2 host only. Never start a second deployment while a backup exists.
[[ "$(docker inspect cloudlaunch-app --format '{{.State.Status}}')" == running ]] || { echo 'ERROR: Production not running' >&2; exit 1; }
[[ "$(docker inspect cloudlaunch-app --format '{{.HostConfig.RestartPolicy.Name}}')" == unless-stopped ]] || { echo 'ERROR: Unexpected restart policy' >&2; exit 1; }
PORT=$(docker inspect cloudlaunch-app --format '{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostIp}}:{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostPort}}')
[[ "$PORT" == 127.0.0.1:3000 ]] || { echo 'ERROR: Unexpected port binding' >&2; exit 1; }
if docker container inspect cloudlaunch-app-previous >/dev/null 2>&1; then
  echo 'ERROR: Rollback backup already exists. Resolve it before another promotion.' >&2
  exit 1
fi
if docker container inspect cloudlaunch-candidate >/dev/null 2>&1; then
  echo 'ERROR: Candidate container still exists' >&2
  exit 1
fi
curl -fsS http://127.0.0.1:3000/health >/dev/null
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo 'ERROR: Target image must be pulled on EC2 before promotion' >&2
  exit 1
fi

# A stopped backup keeps its original image and port configuration.
# The EXIT trap attempts recovery for failed commands and caught termination signals.
RECOVERY_REQUIRED=0
recover() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if (( RECOVERY_REQUIRED )); then
    echo 'Promotion interrupted/failed; attempting rollback...' >&2
    if docker container inspect cloudlaunch-app-previous >/dev/null 2>&1; then
      if docker container inspect cloudlaunch-app >/dev/null 2>&1; then
        docker rm -f cloudlaunch-app || echo 'CRITICAL: Cannot remove failed container' >&2
      fi
      if ! docker container inspect cloudlaunch-app >/dev/null 2>&1; then
        if docker rename cloudlaunch-app-previous cloudlaunch-app && \
           docker update --restart=unless-stopped cloudlaunch-app && \
           docker start cloudlaunch-app; then
          local healthy=0
          for _ in $(seq 1 15); do
            if curl -fsS http://127.0.0.1:3000/health >/dev/null 2>&1; then healthy=1; break; fi
            sleep 2
          done
          if (( healthy )); then echo 'Rollback restored healthy production.' >&2
          else echo 'CRITICAL: Restored production is not healthy' >&2; fi
        else
          echo 'CRITICAL: Automatic rollback failed. Manual recovery required.' >&2
        fi
      else
        echo 'CRITICAL: Failed container blocks rollback; backup preserved.' >&2
      fi
    else
      # Stop or rename may have failed before the backup was created.
      if docker container inspect cloudlaunch-app >/dev/null 2>&1; then
        docker update --restart=unless-stopped cloudlaunch-app || true
        docker start cloudlaunch-app || true
      else
        echo 'CRITICAL: Production container and backup not found.' >&2
      fi
    fi
  fi
  exit "$rc"
}
trap recover EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

RECOVERY_REQUIRED=1
echo 'Stopping old production and preserving rollback backup...'
docker update --restart=no cloudlaunch-app
docker stop cloudlaunch-app
docker rename cloudlaunch-app cloudlaunch-app-previous
# Preserve the expected policy so manual rollback can restore the backup.
docker update --restart=unless-stopped cloudlaunch-app-previous

echo 'Starting new production...'
docker run -d --name cloudlaunch-app --memory=128m \
  --restart=unless-stopped -p 127.0.0.1:3000:3000 "$IMAGE"

for _ in $(seq 1 15); do
  if curl -fsS http://127.0.0.1:3000/health >/dev/null 2>&1; then
    RECOVERY_REQUIRED=0
    echo 'Promotion successful. Backup retained as cloudlaunch-app-previous.'
    exit 0
  fi
  sleep 2
done
echo 'ERROR: New production failed health check' >&2
exit 1
