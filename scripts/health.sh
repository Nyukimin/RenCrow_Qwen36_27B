#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "backend ${QWEN36_BACKEND_BASE}/health"
health_payload="$(curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/health")"
printf '%s' "${health_payload}"
printf '\n'

if [[ "${QWEN36_APC_ENABLED}" == "1" ]]; then
  HEALTH_PAYLOAD="${health_payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["HEALTH_PAYLOAD"])
if payload.get("apc_enabled") is not True:
    raise SystemExit("backend health reports apc_enabled=false")
PY
fi

echo "backend ${QWEN36_BACKEND_BASE}/v1/cache/stats"
curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/v1/cache/stats"
printf '\n'

echo "proxy ${QWEN36_PROXY_BASE}/health"
curl -fsS --max-time 5 "${QWEN36_PROXY_BASE}/health"
printf '\n'

echo "listener"
lsof -nP -iTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN
