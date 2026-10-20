#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${ROLLBACK_ENABLED:-false}" != true ]]; then
  echo 'DRY RUN: Production rollback is disabled.'
  echo 'No containers were changed.'
  exit 0
fi

# Defaults preserve existing production behavior.
APP_NAME="${APP_NAME:-cloudlaunch-app}"
PREVIOUS_NAME="${PREVIOUS_NAME:-cloudlaunch-app-previous}"
FAILED_NAME="${FAILED_NAME:-cloudlaunch-app-failed}"
HEALTH_PORT="${HEALTH_PORT:-3000}"
LOCK_FILE="${LOCK_FILE:-/var/lock/cloudlaunch-deploy.lock}"

# Share the same lock as the deployment SSM command.
exec 9>"$LOCK_FILE"
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
    http://127.0.0.1:${HEALTH_PORT}/health >/dev/null 2>&1
}

# Preflight: do not modify production until all checks pass.
exists "${PREVIOUS_NAME}" || {
  echo 'ERROR: Rollback backup does not exist.' >&2
  exit 1
}

exists "${APP_NAME}" || {
  echo 'ERROR: Current production container does not exist.' >&2
  exit 1
}

if exists "${FAILED_NAME}"; then
  echo 'ERROR: Diagnostic container already exists.' >&2
  exit 1
fi

PORT=$(docker inspect "${PREVIOUS_NAME}" \
  --format '{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostIp}}:{{(index (index .HostConfig.PortBindings "3000/tcp") 0).HostPort}}')

[[ "$PORT" == "127.0.0.1:${HEALTH_PORT}" ]] || {
  echo 'ERROR: Backup port binding is invalid.' >&2
  exit 1
}

[[ "$(status "${PREVIOUS_NAME}")" == exited ||
   "$(status "${PREVIOUS_NAME}")" == created ]] || {
  echo 'ERROR: Backup must be stopped.' >&2
  exit 1
}

[[ "$(status "${APP_NAME}")" == running ]] || {
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
  if exists "${FAILED_NAME}"; then

    # The backup may now occupy the production name.
    if exists "${APP_NAME}"; then
      if [[ "$(status "${APP_NAME}")" == running ]] && health; then
        echo 'WARNING: Current production is healthy; preserving it.' >&2
        echo 'Manual inspection required before further changes.' >&2
        return 1
      fi

      if exists "${PREVIOUS_NAME}"; then
        echo 'CRITICAL: Both production and backup names exist.' >&2
        echo 'Manual inspection required; no names overwritten.' >&2
        return 1
      fi

      docker update --restart=no "${APP_NAME}" || true
      docker stop "${APP_NAME}" || true

      if ! docker rename "${APP_NAME}" "${PREVIOUS_NAME}"; then
        echo 'CRITICAL: Cannot preserve restored backup.' >&2
        return 1
      fi
    fi

    if ! docker rename "${FAILED_NAME}" "${APP_NAME}"; then
      echo 'CRITICAL: Cannot restore original container name.' >&2
      return 1
    fi
  fi

  # Original production may still have its original name.
  if exists "${APP_NAME}"; then
    docker update --restart=unless-stopped "${APP_NAME}" || true
    docker start "${APP_NAME}" || true

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

docker update --restart=no "${APP_NAME}"
docker stop "${APP_NAME}"
docker rename "${APP_NAME}" "${FAILED_NAME}"

docker rename "${PREVIOUS_NAME}" "${APP_NAME}"
docker update --restart=unless-stopped "${APP_NAME}"
docker start "${APP_NAME}"

for _ in $(seq 1 15); do
  if health; then
    ROLLBACK_COMPLETE=true
    RECOVERY_ACTIVE=false
    echo 'Rollback successful.'
    echo "Previous deployment retained as ${FAILED_NAME}."
    exit 0
  fi
  sleep 2
done

echo 'ERROR: Restored production failed health check.' >&2
exit 1
