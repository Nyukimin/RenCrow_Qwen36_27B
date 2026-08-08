#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

if [[ ! -x "${QWEN36_LLAMA_SERVER}" ]]; then
  echo "llama-server not executable: ${QWEN36_LLAMA_SERVER}" >&2
  exit 1
fi

exec "${QWEN36_LLAMA_SERVER}" "$@" \
  --alias "${QWEN36_LLAMA_ALIASES}" \
  --cache-ram "${QWEN36_LLAMA_CACHE_RAM_MIB}" \
  --checkpoint-min-step "${QWEN36_LLAMA_CHECKPOINT_MIN_STEP}" \
  --ctx-checkpoints "${QWEN36_LLAMA_CTX_CHECKPOINTS}" \
  --metrics
