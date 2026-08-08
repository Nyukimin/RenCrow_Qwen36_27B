#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
mkdir -p "${QWEN36_RUN_DIR}"

operation_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
old_instance_id=""
host_identity="$(hostname -f 2>/dev/null || hostname)"
config_revision="$(shasum -a 256 "${ENV_FILE}" "${SCRIPT_DIR}/start.sh" "${SCRIPT_DIR}/stop.sh" "${SCRIPT_DIR}/restart.sh" | shasum -a 256 | awk '{print $1}')"

audit() {
  local outcome="$1" code="$2"
  printf '{"time":"%s","operation_id":"%s","task_id":"%s","old_instance_id":"%s","new_instance_id":"","host_identity":"%s","transport":"tcp","bind_host":"%s","reserved_port":%s,"config_revision":"%s","action":"stop","outcome":"%s","code":"%s"}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${operation_id}" "${QWEN36_TASK_ID}" \
    "${old_instance_id}" "${host_identity}" "${QWEN36_HOST}" "${QWEN36_BACKEND_PORT}" \
    "${config_revision}" "${outcome}" "${code}" >>"${QWEN36_AUDIT_LOG}"
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
  local command_line
  command_line="$(ps -ww -p "$1" -o command= 2>/dev/null || true)"
  [[ -n "${command_line}" && "${command_line}" == *"${QWEN36_MODEL}"* ]] || return 1
  if [[ "${QWEN36_BACKEND_TYPE}" == "llamacpp" ]]; then
    [[ "${command_line}" == *"${QWEN36_LLAMA_SERVER}"* ]]
  else
    [[ "${command_line}" == *"mlx_vlm.server"* || "${command_line}" == *"${QWEN36_RENCROW_START_SCRIPT}"* ]]
  fi
}

pids="$(listener_pids)"
if [[ -z "${pids}" ]]; then
  rm -f "${QWEN36_PID}" "${QWEN36_OWNER_FILE}"
  audit "succeeded" "OK"
  echo "stopped task_id=${QWEN36_TASK_ID}; reserved port ${QWEN36_BACKEND_PORT} was already free"
  exit 0
fi

recorded_pid="$(sed -n 's/^pid=//p' "${QWEN36_OWNER_FILE}" 2>/dev/null | head -1 || true)"
first_pid="$(printf '%s\n' ${pids} | head -1)"
if [[ -n "${recorded_pid}" && "${recorded_pid}" == "${first_pid}" ]]; then
  recorded_task_id="$(sed -n 's/^task_id=//p' "${QWEN36_OWNER_FILE}" | head -1)"
  recorded_start="$(sed -n 's/^process_start_identity=//p' "${QWEN36_OWNER_FILE}" | head -1)"
  current_start="$(ps -ww -p "${recorded_pid}" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  [[ "${recorded_task_id}" == "${QWEN36_TASK_ID}" && -n "${recorded_start}" && "${recorded_start}" == "${current_start}" ]] || \
    fail "PORT_OWNERSHIP_CONFLICT" "owner record does not match the live task instance"
  old_instance_id="$(sed -n 's/^instance_id=//p' "${QWEN36_OWNER_FILE}" | head -1)"
fi
for pid in ${pids}; do
  owned_pid "${pid}" || fail "PORT_OWNERSHIP_CONFLICT" "reserved port ${QWEN36_BACKEND_PORT} is owned by unverified pid=${pid}"
done
for pid in ${pids}; do
  kill "${pid}"
done

elapsed=0
while [[ "${elapsed}" -lt "${QWEN36_STOP_TIMEOUT}" ]]; do
  running=""
  for pid in ${pids}; do
    kill -0 "${pid}" >/dev/null 2>&1 && running="${running} ${pid}"
  done
  [[ -z "$(listener_pids)" && -z "${running}" ]] && break
  sleep 1
  elapsed=$((elapsed + 1))
done
[[ -z "$(listener_pids)" ]] || fail "PORT_RELEASE_TIMEOUT" "reserved port ${QWEN36_BACKEND_PORT} was not released"
for pid in ${pids}; do
  kill -0 "${pid}" >/dev/null 2>&1 && fail "PORT_RELEASE_TIMEOUT" "owned pid=${pid} did not exit"
done
rm -f "${QWEN36_PID}" "${QWEN36_OWNER_FILE}"
audit "succeeded" "OK"
echo "stopped task_id=${QWEN36_TASK_ID} reserved_port=${QWEN36_BACKEND_PORT}"
