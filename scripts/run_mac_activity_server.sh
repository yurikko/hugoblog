#!/bin/bash
set -euo pipefail

ROOT_DIR="/Users/miya/Blogs"
ENV_FILE="${ROOT_DIR}/launchd/mac-activity.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

HOST="${MAC_ACTIVITY_HOST:-127.0.0.1}"
PORT="${MAC_ACTIVITY_PORT:-48123}"
API_KEY="${MAC_ACTIVITY_API_KEY:-}"
CORS_ORIGINS="${MAC_ACTIVITY_CORS_ORIGINS:-}"

if [[ -z "${API_KEY}" ]]; then
  echo "MAC_ACTIVITY_API_KEY is required in ${ENV_FILE}" >&2
  exit 1
fi

ARGS=(
  "${ROOT_DIR}/scripts/mac_activity_server.py"
  "--host" "${HOST}"
  "--port" "${PORT}"
  "--api-key" "${API_KEY}"
)

IFS=',' read -r -a ORIGIN_ARRAY <<< "${CORS_ORIGINS}"
for origin in "${ORIGIN_ARRAY[@]}"; do
  trimmed_origin="$(echo "${origin}" | xargs)"
  if [[ -n "${trimmed_origin}" ]]; then
    ARGS+=("--cors-origin" "${trimmed_origin}")
  fi
done

exec /usr/bin/python3 "${ARGS[@]}"
