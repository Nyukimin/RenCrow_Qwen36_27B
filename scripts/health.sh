#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "backend ${QWEN36_BACKEND_BASE}/health"
curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/health"
printf '\n'

echo "proxy ${QWEN36_PROXY_BASE}/health"
curl -fsS --max-time 5 "${QWEN36_PROXY_BASE}/health"
printf '\n'

echo "listener"
lsof -nP -iTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN
