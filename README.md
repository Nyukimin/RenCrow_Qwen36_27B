# RenCrow Qwen3.6 27B runtime

This repo owns the local optimized runtime wrapper for the current RenCrow Wild
backend:

- frontend proxy: `http://127.0.0.1:8084`
- backend server: `http://127.0.0.1:18084`
- model: `/Users/yukimi/models/Qwen3.6-27B-Uncensored-Heretic-v2-MLX-4bit`
- Python runtime: `/Users/yukimi/RenCrow/RenCrow_LLM/.venv/bin/python3`
- process cwd: `/Users/yukimi/RenCrow/RenCrow_LLM`
- stable start path: `/Users/yukimi/RenCrow/RenCrow_LLM/scripts/start_mlx_vlm_backend.sh Wild`

The wrapper keeps the public RenCrow endpoint unchanged and only changes how
the MLX backend is started.

Automatic Prefix Cache is enabled by default through `QWEN36_APC_ENABLED=1`.
The backend owns the cache, and `scripts/health.sh` fails when `/health` does
not report `apc_enabled=true`. `/v1/cache/stats` is printed for hit validation.

By default `scripts/start.sh` delegates to the verified RenCrow_LLM start script.
Direct `mlx_vlm.server` startup can be tested with `QWEN36_DIRECT_START=1`, but
runtime tuning flags are intentionally opt-in. In this local `mlx_vlm` build,
`--max-kv-size`, 4-bit uniform KV, and even an explicit `--max-tokens 8192`
start and pass `/health`, but the backend exits on the first generation request
for this Qwen3.6 model.

## Commands

```bash
scripts/health.sh
scripts/bench.sh
scripts/restart.sh
```

`scripts/restart.sh` replaces only the process listening on backend port
`18084`. The `8084` RenCrow proxy is left running. By default it starts Wild
through the RenCrow mgmt API so the backend is owned by the same daemon as the
current production process.

All defaults live in `config/qwen36.env` and can be overridden through
environment variables.
