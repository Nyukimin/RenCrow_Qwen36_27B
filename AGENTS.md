# AGENTS.md

## Classification

This repository is a host-specific LLM external runtime profile owned by
`RenCrow_LLM`. It is not a RenCrow module, Agent, routing owner, Public API, or
CORE integration boundary. When present, `/home/nyukimi/RenCrow/AGENTS.md`
also applies.

The only canonical production route is:

```text
RenCrow_CORE -> RenCrow LLM Gateway -> RenCrow LLM Runtime -> Backend -> Model
```

Keep only Qwen Backend launch, health, benchmark, and host tuning here. Do not
place Persona, Agent identity, semantic routing, CORE API behavior,
credentials, model weights, runtime logs, caches, or generated artifacts here.

Do not create a direct CORE/backend route or substitute this profile for the
RenCrow LLM Runtime. Restart, model download, external publication, commit, and
push require explicit user instruction. Do not create a branch unless asked.

Before reporting runtime success, distinguish wrapper process liveness,
Backend health, Model readiness, and an actual generation through the owning
RenCrow_LLM route.
