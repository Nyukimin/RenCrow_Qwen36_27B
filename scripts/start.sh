#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

if [[ ! -e "${QWEN36_MODEL}" ]]; then
  echo "model not found: ${QWEN36_MODEL}" >&2
  exit 1
fi
if [[ ! -d "${QWEN36_RUNTIME_CWD}" ]]; then
  echo "runtime cwd not found: ${QWEN36_RUNTIME_CWD}" >&2
  exit 1
fi
if [[ "${QWEN36_BACKEND_TYPE}" == "mlx" && "${QWEN36_DIRECT_START}" != "1" && ! -x "${QWEN36_RENCROW_START_SCRIPT}" ]]; then
  echo "RenCrow start script not executable: ${QWEN36_RENCROW_START_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${QWEN36_RUN_DIR}"
cd "${QWEN36_RUNTIME_CWD}"

if [[ "${QWEN36_BACKEND_TYPE}" == "llamacpp" ]]; then
  exec "${SCRIPT_DIR}/llama-server.sh" \
    -m "${QWEN36_MODEL}" \
    --host "${QWEN36_HOST}" \
    --port "${QWEN36_BACKEND_PORT}" \
    -c "${QWEN36_LLAMA_CONTEXT_SIZE}" \
    -np "${QWEN36_LLAMA_PARALLEL}" \
    --prio 3 \
    --prio-batch 3 \
    -ngl "${QWEN36_LLAMA_GPU_LAYERS}" \
    --flash-attn "${QWEN36_LLAMA_FLASH_ATTN}" \
    --cache-type-k "${QWEN36_LLAMA_CACHE_TYPE_K}" \
    --cache-type-v "${QWEN36_LLAMA_CACHE_TYPE_V}" \
    --jinja
fi

if [[ "${QWEN36_BACKEND_TYPE}" != "mlx" ]]; then
  echo "unsupported backend type: ${QWEN36_BACKEND_TYPE}" >&2
  exit 1
fi
if [[ ! -x "${QWEN36_PYTHON}" ]]; then
  echo "python not executable: ${QWEN36_PYTHON}" >&2
  exit 1
fi
if [[ ! -d "${QWEN36_MODEL}" ]]; then
  echo "MLX model directory not found: ${QWEN36_MODEL}" >&2
  exit 1
fi

export APC_ENABLED="${QWEN36_APC_ENABLED}"
export APC_BLOCK_SIZE="${QWEN36_APC_BLOCK_SIZE}"
export APC_NUM_BLOCKS="${QWEN36_APC_NUM_BLOCKS}"

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
