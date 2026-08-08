#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "backend ${QWEN36_BACKEND_BASE}/health"
health_payload="$(curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/health")"
printf '%s' "${health_payload}"
printf '\n'

if [[ "${QWEN36_BACKEND_TYPE}" == "llamacpp" ]]; then
  HEALTH_PAYLOAD="${health_payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["HEALTH_PAYLOAD"])
if payload.get("status") != "ok":
    raise SystemExit("llama.cpp backend health is not ok")
PY

  echo "backend ${QWEN36_BACKEND_BASE}/v1/models"
  models_payload="$(curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/v1/models")"
  printf '%s\n' "${models_payload}"
  MODELS_PAYLOAD="${models_payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["MODELS_PAYLOAD"])
models = {item.get("id") for item in payload.get("data", [])}
if "Wild" not in models:
    raise SystemExit(f"llama.cpp model alias Wild not ready: {sorted(models)}")
PY

  echo "backend ${QWEN36_BACKEND_BASE}/slots"
  slots_payload="$(curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/slots")"
  printf '%s\n' "${slots_payload}"
  SLOTS_PAYLOAD="${slots_payload}" EXPECTED_CTX="${QWEN36_LLAMA_CONTEXT_SIZE}" python3 - <<'PY'
import json
import os

slots = json.loads(os.environ["SLOTS_PAYLOAD"])
expected = int(os.environ["EXPECTED_CTX"])
if len(slots) != 1 or slots[0].get("n_ctx") != expected:
    raise SystemExit(f"unexpected llama.cpp slots: {slots}")
PY

  metrics_payload="$(curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/metrics")"
  if ! grep -q '^llamacpp:' <<<"${metrics_payload}"; then
    echo "llama.cpp metrics unavailable" >&2
    exit 1
  fi
elif [[ "${QWEN36_APC_ENABLED}" == "1" ]]; then
  HEALTH_PAYLOAD="${health_payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["HEALTH_PAYLOAD"])
if payload.get("apc_enabled") is not True:
    raise SystemExit("backend health reports apc_enabled=false")
PY
  echo "backend ${QWEN36_BACKEND_BASE}/v1/cache/stats"
  curl -fsS --max-time 5 "${QWEN36_BACKEND_BASE}/v1/cache/stats"
  printf '\n'
fi

echo "proxy ${QWEN36_PROXY_BASE}/health"
curl -fsS --max-time 5 "${QWEN36_PROXY_BASE}/health"
printf '\n'

echo "listener"
lsof -nP -iTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN
