#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

if [[ ! -x "${QWEN36_PYTHON}" ]]; then
  echo "python not executable: ${QWEN36_PYTHON}" >&2
  exit 1
fi
if [[ ! -d "${QWEN36_MODEL}" ]]; then
  echo "model directory not found: ${QWEN36_MODEL}" >&2
  exit 1
fi
if [[ ! -d "${QWEN36_RUNTIME_CWD}" ]]; then
  echo "runtime cwd not found: ${QWEN36_RUNTIME_CWD}" >&2
  exit 1
fi
if [[ "${QWEN36_DIRECT_START}" != "1" && ! -x "${QWEN36_RENCROW_START_SCRIPT}" ]]; then
  echo "RenCrow start script not executable: ${QWEN36_RENCROW_START_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${QWEN36_RUN_DIR}"
cd "${QWEN36_RUNTIME_CWD}"

if [[ "${QWEN36_DIRECT_START}" != "1" ]]; then
  exec "${QWEN36_RENCROW_START_SCRIPT}" Wild
fi

command=(
  "${QWEN36_PYTHON}" -m mlx_vlm.server
  --host "${QWEN36_HOST}" \
  --port "${QWEN36_BACKEND_PORT}" \
  --model "${QWEN36_MODEL}"
)

if [[ -n "${QWEN36_PREFILL_STEP_SIZE}" ]]; then
  command+=(--prefill-step-size "${QWEN36_PREFILL_STEP_SIZE}")
fi

if [[ -n "${QWEN36_MAX_TOKENS}" ]]; then
  command+=(--max-tokens "${QWEN36_MAX_TOKENS}")
fi

if [[ -n "${QWEN36_MAX_KV_SIZE}" ]]; then
  command+=(--max-kv-size "${QWEN36_MAX_KV_SIZE}")
fi

if [[ -n "${QWEN36_KV_BITS}" ]]; then
  command+=(
    --kv-bits "${QWEN36_KV_BITS}"
    --kv-quant-scheme "${QWEN36_KV_QUANT_SCHEME}"
    --kv-group-size "${QWEN36_KV_GROUP_SIZE}"
    --quantized-kv-start "${QWEN36_QUANTIZED_KV_START}"
  )
fi

exec "${command[@]}"
