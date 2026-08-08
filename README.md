# RenCrow Qwen3.6 27B runtime

This repo owns the local optimized runtime wrapper for the current RenCrow Wild
backend:

- frontend proxy: `http://127.0.0.1:8084`
- backend server: `http://127.0.0.1:18084`
- Backend: llama.cpp b10327
- model: `/Users/yukimi/models/Qwen3.6-27B-Uncensored-Heretic-v2-GGUF/Qwen3.6-27B-uncensored-heretic-v2-Q4_K_M.gguf`
- runtime: `/Users/yukimi/.rencrow/runtimes/llama.cpp/b10327/llama-server`
- process cwd: `/Users/yukimi/RenCrow/RenCrow_LLM`
- stable wrapper: `scripts/llama-server.sh`

The wrapper keeps the public RenCrow endpoint unchanged and changes only the
Backend engine behind the RenCrow LLM Runtime.

With `QWEN36_USE_MGMT=1`, the deployed RenCrow_LLM Wild role config must use
`backend_type = "llamacpp"` and set `llamacpp_command` to this repository's
`scripts/llama-server.sh`. The mgmt daemon then owns boot/restart lifecycle;
the wrapper owns only Qwen-specific Backend tuning.

llama.cpp prompt caching is enabled by default. Qwen3.6 uses hybrid recurrent
and full-attention layers, so `QWEN36_LLAMA_CHECKPOINT_MIN_STEP=256` keeps a
checkpoint close to the stable SystemPrompt boundary. `scripts/health.sh`
checks Backend health, the `Wild` model alias, the 65,536-token slot, metrics,
the unchanged proxy, and the listener.

The MLX runtime remains an explicit fallback by setting
`QWEN36_BACKEND_TYPE=mlx` and an MLX model directory. It is not the default:
its exact-only APC reused a fully identical request but reprocessed the stable
4.4K-token prefix whenever the final user message changed.

On the measured Midori payload, the suffix-change TTFT moved from 14.04 seconds
with MLX to 0.94 seconds with llama.cpp, with 4,440 of 4,484 input tokens reused.
Cold TTFT is not improved (17.19 seconds versus 15.56 seconds); the gain comes
from correct conversation-prefix reuse.

## Commands

```bash
scripts/health.sh
scripts/bench.sh
scripts/restart.sh
```

`scripts/restart.sh` must first verify that the listener on reserved backend
port `18084` belongs to the current Wild task, then replace only that task. An
unknown or different owner is a conflict and is not stopped. The `8084` RenCrow proxy is left running. By default it starts Wild
through the RenCrow mgmt API so the backend is owned by the same daemon as the
current production process.

It never selects another port when `18084` is occupied. Task identity, release
verification, same-port startup, and failure semantics follow the
[RenCrow_CORE reserved-port contract](https://github.com/Nyukimin/RenCrow_CORE/blob/main/docs/04_アーキテクチャ概要.md#予約portと同一taskの置換起動契約).
The reservation value itself remains owned by the RenCrow_LLM host config.

All defaults live in `config/qwen36.env` and can be overridden through
environment variables.
