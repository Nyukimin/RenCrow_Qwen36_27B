#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

mkdir -p "${QWEN36_RUN_DIR}"

operation_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
new_instance_id="${operation_id}"
old_instance_id=""
host_identity="$(hostname -f 2>/dev/null || hostname)"
config_revision="$(shasum -a 256 "${ENV_FILE}" "${SCRIPT_DIR}/start.sh" "${SCRIPT_DIR}/stop.sh" "${SCRIPT_DIR}/restart.sh" | shasum -a 256 | awk '{print $1}')"

audit() {
  local outcome="$1"
  local code="$2"
  printf '{"time":"%s","operation_id":"%s","task_id":"%s","old_instance_id":"%s","new_instance_id":"%s","host_identity":"%s","transport":"tcp","bind_host":"%s","reserved_port":%s,"config_revision":"%s","action":"replace","outcome":"%s","code":"%s"}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${operation_id}" "${QWEN36_TASK_ID}" \
    "${old_instance_id}" "${new_instance_id}" "${host_identity}" "${QWEN36_HOST}" \
    "${QWEN36_BACKEND_PORT}" "${config_revision}" "${outcome}" "${code}" >>"${QWEN36_AUDIT_LOG}"
}

fail() {
  local code="$1"
  shift
  audit "failed" "${code}"
  printf '%s: %s\n' "${code}" "$*" >&2
  exit 1
}

if ! mkdir "${QWEN36_LOCK_DIR}" 2>/dev/null; then
  lock_owner="$(cat "${QWEN36_LOCK_DIR}/owner.pid" 2>/dev/null || true)"
  if [[ "${lock_owner}" =~ ^[0-9]+$ ]] && kill -0 "${lock_owner}" 2>/dev/null; then
    fail "LIFECYCLE_BUSY" "another ${QWEN36_TASK_ID} lifecycle operation is active: pid=${lock_owner}"
  fi
  rm -f "${QWEN36_LOCK_DIR}/owner.pid"
  rmdir "${QWEN36_LOCK_DIR}" 2>/dev/null || true
  mkdir "${QWEN36_LOCK_DIR}" 2>/dev/null || fail "LIFECYCLE_BUSY" "could not acquire ${QWEN36_TASK_ID} lifecycle lock"
fi
printf '%s\n' "$$" >"${QWEN36_LOCK_DIR}/owner.pid"
trap 'rm -f "${QWEN36_LOCK_DIR}/owner.pid"; rmdir "${QWEN36_LOCK_DIR}" 2>/dev/null || true' EXIT

listener_pids() {
  lsof -tiTCP:"${QWEN36_BACKEND_PORT}" -sTCP:LISTEN 2>/dev/null || true
}

owned_pid() {
  local pid="$1"
  local command_line
  command_line="$(ps -ww -p "${pid}" -o command= 2>/dev/null || true)"
  [[ -n "${command_line}" ]] || return 1
  [[ "${command_line}" == *"${QWEN36_MODEL}"* ]] || return 1
  if [[ "${QWEN36_BACKEND_TYPE}" == "llamacpp" ]]; then
    [[ "${command_line}" == *"${QWEN36_LLAMA_SERVER}"* ]]
    return
  fi
  [[ "${command_line}" == *"mlx_vlm.server"* || "${command_line}" == *"${QWEN36_RENCROW_START_SCRIPT}"* ]]
}

wait_for_release() {
  local elapsed=0
  while [[ "${elapsed}" -lt "${QWEN36_STOP_TIMEOUT}" ]]; do
    local running=""
    for pid in ${previous_pids:-}; do
      kill -0 "${pid}" >/dev/null 2>&1 && running="${running} ${pid}"
    done
    [[ -z "$(listener_pids)" && -z "${running}" ]] && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  [[ -z "$(listener_pids)" ]] || return 1
  for pid in ${previous_pids:-}; do
    kill -0 "${pid}" >/dev/null 2>&1 && return 1
  done
  return 0
}

previous_pids="$(listener_pids)"
if [[ -n "${previous_pids}" ]]; then
  recorded_pid="$(sed -n 's/^pid=//p' "${QWEN36_OWNER_FILE}" 2>/dev/null | head -1 || true)"
  if [[ -n "${recorded_pid}" && "${recorded_pid}" == "$(printf '%s\n' ${previous_pids} | head -1)" ]]; then
    recorded_task_id="$(sed -n 's/^task_id=//p' "${QWEN36_OWNER_FILE}" 2>/dev/null | head -1 || true)"
    recorded_start_identity="$(sed -n 's/^process_start_identity=//p' "${QWEN36_OWNER_FILE}" 2>/dev/null | head -1 || true)"
    current_start_identity="$(ps -ww -p "${recorded_pid}" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
    if [[ "${recorded_task_id}" != "${QWEN36_TASK_ID}" || -z "${recorded_start_identity}" || "${recorded_start_identity}" != "${current_start_identity}" ]]; then
      fail "PORT_OWNERSHIP_CONFLICT" "owner record does not match the live task instance on reserved port ${QWEN36_BACKEND_PORT}"
    fi
    old_instance_id="$(sed -n 's/^instance_id=//p' "${QWEN36_OWNER_FILE}" 2>/dev/null | head -1 || true)"
  fi
  for pid in ${previous_pids}; do
    if ! owned_pid "${pid}"; then
      fail "PORT_OWNERSHIP_CONFLICT" "reserved port ${QWEN36_BACKEND_PORT} is owned by unverified pid=${pid}"
    fi
  done
  echo "stopping ${QWEN36_TASK_ID} listener(s) on reserved port ${QWEN36_BACKEND_PORT}: ${previous_pids}"
  for pid in ${previous_pids}; do
    kill "${pid}"
  done
  if ! wait_for_release; then
    fail "PORT_RELEASE_TIMEOUT" "reserved port ${QWEN36_BACKEND_PORT} was not released in ${QWEN36_STOP_TIMEOUT}s"
  fi
  rm -f "${QWEN36_PID}" "${QWEN36_OWNER_FILE}"
fi

mgmt_token() {
  if [[ -n "${LLM_OPS_TOKEN:-}" ]]; then
    printf '%s\n' "${LLM_OPS_TOKEN}"
    return 0
  fi

  local pid
  pid="$(pgrep -f 'llm_server\.mgmt_daemon' | head -1 || true)"
  [[ -n "${pid}" ]] || return 1
  ps eww -p "${pid}" | tr ' ' '\n' | sed -n 's/^LLM_OPS_TOKEN=//p' | head -1
}

if [[ "${QWEN36_USE_MGMT}" == "1" ]]; then
  token="$(mgmt_token || true)"
  [[ -n "${token}" ]] || fail "TASK_START_FAILED" "LLM_OPS_TOKEN is unavailable"
  echo "starting ${QWEN36_TASK_ID} through the fixed RenCrow LLM management route"
  if ! curl -fsS \
    --max-time "${QWEN36_START_TIMEOUT}" \
    -H "Authorization: Bearer ${token}" \
    -H 'Content-Type: application/json' \
    -d '{"selection":"Wild"}' \
    "${QWEN36_MGMT_BASE}/v1/control/start" >/dev/null; then
    fail "TASK_START_FAILED" "configured management start failed"
  fi
else
  echo "starting ${QWEN36_TASK_ID} on reserved port ${QWEN36_BACKEND_PORT}"
  nohup "${SCRIPT_DIR}/start.sh" >"${QWEN36_LOG}" 2>&1 &
  launch_pid="$!"
fi

pid=""
launch_pid="${launch_pid:-}"
elapsed=0
while [[ "${elapsed}" -lt "${QWEN36_START_TIMEOUT}" ]]; do
  current_pids="$(listener_pids)"
  if [[ -n "${current_pids}" ]]; then
    for candidate in ${current_pids}; do
      owned_pid "${candidate}" || fail "PORT_OWNERSHIP_CONFLICT" "a different process captured reserved port ${QWEN36_BACKEND_PORT}: pid=${candidate}"
    done
  fi
  if [[ -n "${current_pids}" ]] && curl -fsS --max-time 2 "${QWEN36_BACKEND_BASE}/health" >/dev/null 2>&1; then
    pid="$(printf '%s\n' ${current_pids} | head -1)"
    printf '%s\n' "${pid}" >"${QWEN36_PID}"
    process_start_identity="$(ps -ww -p "${pid}" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
    owner_executable="${QWEN36_LLAMA_SERVER}"
    [[ "${QWEN36_BACKEND_TYPE}" == "mlx" ]] && owner_executable="${QWEN36_PYTHON}"
    owner_tmp="${QWEN36_OWNER_FILE}.tmp.$$"
    {
      printf 'task_id=%s\n' "${QWEN36_TASK_ID}"
      printf 'instance_id=%s\n' "${new_instance_id}"
      printf 'pid=%s\n' "${pid}"
      printf 'process_start_identity=%s\n' "${process_start_identity}"
      printf 'executable=%s\n' "${owner_executable}"
      printf 'config_revision=%s\n' "${config_revision}"
      printf 'host_identity=%s\n' "${host_identity}"
      printf 'bind_host=%s\n' "${QWEN36_HOST}"
      printf 'port=%s\n' "${QWEN36_BACKEND_PORT}"
    } >"${owner_tmp}"
    mv "${owner_tmp}" "${QWEN36_OWNER_FILE}"
    audit "succeeded" "OK"
    echo "started task_id=${QWEN36_TASK_ID} pid=${pid} reserved_port=${QWEN36_BACKEND_PORT}"
    "${SCRIPT_DIR}/health.sh"
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

cleanup_pids="$(listener_pids)"
[[ -n "${launch_pid}" ]] && cleanup_pids="${cleanup_pids} ${launch_pid}"
for candidate in ${cleanup_pids}; do
  if owned_pid "${candidate}"; then
    kill -0 "${candidate}" >/dev/null 2>&1 && kill "${candidate}" || true
  fi
done
previous_pids="${cleanup_pids}"
wait_for_release || true
rm -f "${QWEN36_PID}" "${QWEN36_OWNER_FILE}"
fail "TASK_START_FAILED" "backend did not become healthy on reserved port ${QWEN36_BACKEND_PORT} within ${QWEN36_START_TIMEOUT}s"
