#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

tmp_body="$(mktemp)"
tmp_out="$(mktemp)"
trap 'rm -f "${tmp_body}" "${tmp_out}"' EXIT

cat >"${tmp_body}" <<'JSON'
{
  "model": "Wild",
  "messages": [
    {
      "role": "user",
      "content": "日本語で一文だけ、現在の応答確認をしてください。"
    }
  ],
  "max_tokens": 64,
  "temperature": 0.2,
  "stream": false
}
JSON

echo "POST ${QWEN36_PROXY_BASE}/v1/chat/completions"
curl -sS \
  -o "${tmp_out}" \
  -w 'http_code=%{http_code} time_total=%{time_total}s\n' \
  -H 'Content-Type: application/json' \
  -d @"${tmp_body}" \
  "${QWEN36_PROXY_BASE}/v1/chat/completions"

cat "${tmp_out}"
printf '\n'
