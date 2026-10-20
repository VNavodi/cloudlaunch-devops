#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${ROLLBACK_ENABLED:-false}" != true ]]; then
  echo 'DRY RUN: Production rollback is disabled.'
  echo 'No containers were changed.'
  exit 0
fi
if ! docker container inspect cloudlaunch-app-previous >/dev/null 2>&1; then
  echo 'ERROR: No rollback backup exists' >&2
  exit 1
fi
PORT=$(docker inspect cloudlaunch-app-previous --format '{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostIp}}:{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostPort}}')
[[ "$PORT" == 127.0.0.1:3000 ]] || { echo 'ERROR: Backup port binding invalid' >&2; exit 1; }
[[ "$(docker inspect cloudlaunch-app-previous --format '{{.State.Status}}')" == exited ]] || { echo 'ERROR: Backup must be stopped' >&2; exit 1; }

echo 'Stopping current production for rollback...'
if docker container inspect cloudlaunch-app >/dev/null 2>&1; then
  docker update --restart=no cloudlaunch-app
  docker stop cloudlaunch-app || { docker update --restart=unless-stopped cloudlaunch-app || true; exit 1; }
  # Keep the failed deployment for diagnostics, unless a previous failed backup exists.
  if docker container inspect cloudlaunch-app-failed >/dev/null 2>&1; then
    echo 'ERROR: cloudlaunch-app-failed exists; leaving current container stopped.' >&2
    docker start cloudlaunch-app || true
    docker update --restart=unless-stopped cloudlaunch-app || true
    exit 1
  fi
  docker rename cloudlaunch-app cloudlaunch-app-failed || { docker start cloudlaunch-app || true; docker update --restart=unless-stopped cloudlaunch-app || true; exit 1; }
fi
if ! docker rename cloudlaunch-app-previous cloudlaunch-app; then
  echo 'CRITICAL: Cannot rename backup. Manual recovery required.' >&2
  exit 1
fi
docker update --restart=unless-stopped cloudlaunch-app
docker start cloudlaunch-app
for _ in $(seq 1 15); do
  if curl -fsS http://127.0.0.1:3000/health >/dev/null 2>&1; then
    echo 'Rollback successful. Failed container retained as cloudlaunch-app-failed.'
    exit 0
  fi
  sleep 2
done
echo 'CRITICAL: Restored production failed health check.' >&2
exit 1
