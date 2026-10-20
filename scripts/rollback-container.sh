#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${ROLLBACK_ENABLED:-false}" != true ]]; then
  echo 'DRY RUN: Production rollback is disabled.'
  echo 'No containers were changed.'
  exit 0
fi

# Share the same lock as the deployment SSM command.
exec 9>/var/lock/cloudlaunch-deploy.lock
flock -n 9 || {
  echo 'ERROR: Another CloudLaunch operation is in progress.' >&2
  exit 1
}

exists() {
  docker container inspect "$1" >/dev/null 2>&1
}

status() {
  docker inspect "$1" --format '{{.State.Status}}'
}

health() {
  curl --max-time 3 -fsS \
    http://127.0.0.1:3000/health >/dev/null 2>&1
}

# Preflight: do not modify production until all checks pass.
exists cloudlaunch-app-previous || {
  echo 'ERROR: Rollback backup does not exist.' >&2
  exit 1
}

exists cloudlaunch-app || {
  echo 'ERROR: Current production container does not exist.' >&2
  exit 1
}

if exists cloudlaunch-app-failed; then
  echo 'ERROR: Diagnostic container already exists.' >&2
  exit 1
fi

PORT=$(docker inspect cloudlaunch-app-previous \
  --format '{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostIp}}:{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostPort}}')

[[ "$PORT" == "127.0.0.1:3000" ]] || {
  echo 'ERROR: Backup port binding is invalid.' >&2
  exit 1
}

[[ "$(status cloudlaunch-app-previous)" == exited ]] || {
  echo 'ERROR: Backup must be stopped.' >&2
  exit 1
}

[[ "$(status cloudlaunch-app)" == running ]] || {
  echo 'ERROR: Production must be running.' >&2
  exit 1
}

health || {
  echo 'ERROR: Production health check failed.' >&2
  exit 1
}

# Enable recovery only after preflight succeeds.
RECOVERY_ACTIVE=false
ROLLBACK_COMPLETE=false

recover() {
  local result=$?
  trap - EXIT

  if [[ "$result" -eq 0 && "$ROLLBACK_COMPLETE" == true ]]; then
    return 0
  fi

  if [[ "$RECOVERY_ACTIVE" != true ]]; then
    return "$result"
  fi

  echo 'WARNING: Rollback incomplete. Attempting recovery.' >&2

  # Original production has already been renamed.
  if exists cloudlaunch-app-failed; then

    # The backup may now occupy the production name.
    if exists cloudlaunch-app; then
      if [[ "$(status cloudlaunch-app)" == running ]] && health; then
        echo 'WARNING: Current production is healthy; preserving it.' >&2
        echo 'Manual inspection required before further changes.' >&2
        return 1
      fi

      if exists cloudlaunch-app-previous; then
        echo 'CRITICAL: Both production and backup names exist.' >&2
        echo 'Manual inspection required; no names overwritten.' >&2
        return 1
      fi

      docker update --restart=no cloudlaunch-app || true
      docker stop cloudlaunch-app || true

      if ! docker rename cloudlaunch-app cloudlaunch-app-previous; then
        echo 'CRITICAL: Cannot preserve restored backup.' >&2
        return 1
      fi
    fi

    if ! docker rename cloudlaunch-app-failed cloudlaunch-app; then
      echo 'CRITICAL: Cannot restore original container name.' >&2
      return 1
    fi
  fi

  # Original production may still have its original name.
  if exists cloudlaunch-app; then
    docker update --restart=unless-stopped cloudlaunch-app || true
    docker start cloudlaunch-app || true

    for _ in $(seq 1 10); do
      if health; then
        echo 'Original production recovered and healthy.' >&2
        return 1
      fi
      sleep 2
    done
  fi

  echo 'CRITICAL: Recovery health not confirmed.' >&2
  echo 'Inspect containers manually before retrying.' >&2
  return 1
}

trap recover EXIT

echo 'Stopping current production for rollback...'
RECOVERY_ACTIVE=true

docker update --restart=no cloudlaunch-app
docker stop cloudlaunch-app
docker rename cloudlaunch-app cloudlaunch-app-failed

docker rename cloudlaunch-app-previous cloudlaunch-app
docker update --restart=unless-stopped cloudlaunch-app
docker start cloudlaunch-app

for _ in $(seq 1 15); do
  if health; then
    ROLLBACK_COMPLETE=true
    RECOVERY_ACTIVE=false
    echo 'Rollback successful.'
    echo 'Previous deployment retained as cloudlaunch-app-failed.'
    exit 0
  fi
  sleep 2
done

echo 'ERROR: Restored production failed health check.' >&2
exit 1
