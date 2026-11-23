# ADR-0001: Plain Monorepo over Umbrella or Separate Repos

**Date:** 2026-08-17
**Status:** Accepted

## Context

Yagye consists of five independently deployable services:

- `yagye_core` — Elixir/Phoenix; payment orchestration and ledger (~76 tables)
- `yagye_portal` — Rails 8; merchant self-service portal (20 tables)
- `yagye_simulator` — Elixir/Phoenix; mock payment gateway for testing (13 tables)
- `yagye_scoring` — Python FastAPI; LLM scoring service (Claude + OpenLIT + Langfuse)
- `yagye_data` — Python; DuckDB-based Silver/Gold ETL pipeline

We needed to decide how to organise these services in version control.

Three options were considered:

**Option A — Separate repos**: one GitHub repository per service. Each service is
completely independent. Teams work autonomously; CI and deployment are fully isolated.

**Option B — Elixir umbrella**: a single `mix.exs` at the root with `apps/` children
that share compilation context, deps resolution, and the OTP supervision tree.

**Option C — Plain monorepo**: each app has its own language-appropriate build file
(`mix.exs`, `Gemfile`, `pyproject.toml`), its own dependencies, its own Dockerfile,
and its own database. They share only the git root, CI config, and infra tooling.

## Decision

We use a **plain monorepo** (`apps/yagye_core`, `apps/yagye_portal`,
`apps/yagye_simulator`, `apps/yagye_scoring`, `apps/yagye_data`).

## Consequences

### Positive
- Each service can be deployed, versioned, and scaled independently.
- Each service has its own database — no accidental cross-service joins.
- Adding a new service requires no changes to the root project structure.
- `yagye_portal` (Rails) fits naturally alongside Elixir apps without the
  friction of an Elixir umbrella trying to wrap a non-Elixir project.
- A single CI pipeline can test all services with per-service working directories.
- Shared tooling (`.tool-versions`, `infra/`, `docs/`) is co-located without
  coupling service dependencies.

### Negative / Trade-offs
- Elixir code cannot be shared as a library between services without publishing
  a private Hex package. Any shared domain types must be duplicated or extracted.
- Each service manages its own `mix.lock`; dependency drift between services is
  possible and must be managed manually.
- CI runtime grows with each service added; caching strategy must be per-service.
