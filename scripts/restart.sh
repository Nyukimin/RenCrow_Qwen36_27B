#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

mkdir -p "${QWEN36_RUN_DIR}"

mgmt_token() {
  if [[ -n "${LLM_OPS_TOKEN:-}" ]]; then
    printf '%s\n' "${LLM_OPS_TOKEN}"
    return 0
  fi

  local pid
  pid="$(pgrep -f 'llm_server\.mgmt_daemon' | head -1 || true)"
  if [[ -z "${pid}" ]]; then
    return 1
  fi

  ps eww -p "${pid}" | tr ' ' '\n' | sed -n 's/^LLM_OPS_TOKEN=//p' | head -1
}

existing_pids="$(lsof -tiTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN || true)"
if [[ -n "${existing_pids}" ]]; then
  echo "stopping backend listener(s) on ${QWEN36_BACKEND_PORT}: ${existing_pids}"
  kill ${existing_pids}
  for _ in {1..30}; do
    if ! lsof -tiTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

if lsof -tiTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "backend port still busy after graceful stop: ${QWEN36_BACKEND_PORT}" >&2
  exit 1
fi

if [[ "${QWEN36_USE_MGMT}" == "1" ]]; then
  token="$(mgmt_token || true)"
  if [[ -z "${token}" ]]; then
    echo "LLM_OPS_TOKEN not available and mgmt daemon token could not be read" >&2
    exit 1
  fi
  echo "starting Qwen3.6 backend through mgmt API"
  curl -fsS \
    --max-time 180 \
    -H "Authorization: Bearer ${token}" \
    -H 'Content-Type: application/json' \
    -d '{"selection":"Wild"}' \
    "${QWEN36_MGMT_BASE}/v1/control/start" >/dev/null
  pid="$(lsof -tiTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN | head -1)"
else
  echo "starting Qwen3.6 backend directly on ${QWEN36_HOST}:${QWEN36_BACKEND_PORT}"
  nohup "${SCRIPT_DIR}/start.sh" >"${QWEN36_LOG}" 2>&1 &
  pid="$!"
fi

printf '%s\n' "${pid}" >"${QWEN36_PID}"

for _ in {1..120}; do
  if curl -fsS --max-time 2 "${QWEN36_BACKEND_BASE}/health" >/dev/null 2>&1; then
    echo "started pid=${pid}"
    "${SCRIPT_DIR}/health.sh"
    exit 0
  fi
  if [[ -n "${pid}" ]]; then
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      echo "backend exited during startup; see ${QWEN36_LOG}" >&2
      tail -40 "${QWEN36_LOG}" >&2 || true
      exit 1
    fi
  fi
  sleep 1
done

echo "backend did not become healthy within 120s; see ${QWEN36_LOG}" >&2
exit 1
