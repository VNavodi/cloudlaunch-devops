#!/usr/bin/env bash
set -euo pipefail

if [[ "${ROLLBACK_ENABLED:-false}" != "true" ]]; then
  echo "DRY RUN: Production rollback is disabled."
  echo "No containers were changed."
  exit 0
fi

echo "Checking for previous CloudLaunch container..."

if ! docker container inspect cloudlaunch-app-previous >/dev/null 2>&1; then
  echo "ERROR: No previous container found."
  exit 1
fi
echo "Validating rollback backup..."

BACKUP_IMAGE=$(docker inspect cloudlaunch-app-previous \
  --format '{{.Image}}')

BACKUP_RESTART=$(docker inspect cloudlaunch-app-previous \
  --format '{{.HostConfig.RestartPolicy.Name}}')

BACKUP_PORT=$(docker inspect cloudlaunch-app-previous \
  --format '{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostIp}}:{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostPort}}')

if [[ -z "$BACKUP_IMAGE" ||
      "$BACKUP_RESTART" != "unless-stopped" ||
      "$BACKUP_PORT" != "127.0.0.1:3000" ]]; then
  echo "ERROR: Invalid rollback backup configuration."
  exit 1
fi

echo "Rollback backup configuration verified."

echo "Stopping failed deployment if present..."

if docker container inspect cloudlaunch-app >/dev/null 2>&1; then
  docker stop cloudlaunch-app
  docker rm cloudlaunch-app
fi

echo "Restoring previous container..."

docker rename cloudlaunch-app-previous cloudlaunch-app
docker start cloudlaunch-app

echo "Checking restored application..."

for attempt in $(seq 1 10); do
  if curl -fsS http://127.0.0.1:3000/health; then
    echo
    echo "Rollback successful!"
    exit 0
  fi
  sleep 2
done

echo "ERROR: Restored container failed health check."
exit 1
