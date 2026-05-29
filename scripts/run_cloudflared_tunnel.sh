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

CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-/opt/homebrew/bin/cloudflared}"
CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-/Users/miya/.cloudflared/config.yml}"
CLOUDFLARED_TUNNEL_NAME="${CLOUDFLARED_TUNNEL_NAME:-}"

if [[ -z "${CLOUDFLARED_TUNNEL_NAME}" ]]; then
  echo "CLOUDFLARED_TUNNEL_NAME is required in ${ENV_FILE}" >&2
  exit 1
fi

exec "${CLOUDFLARED_BIN}" tunnel --config "${CLOUDFLARED_CONFIG}" run "${CLOUDFLARED_TUNNEL_NAME}"
