# Yagye

A payment orchestration, settlement and reconciliation platform, built phase by phase
from `finflow-build-bible-v20.docx` ("the bible"). Every architectural decision traces
back to one question the book keeps asking: **where is my money, and can you prove it?**

This is a from-scratch build, not a fork of anything. Nothing here works yet — see
[`BUILD_PLAN.md`](./BUILD_PLAN.md) for what phase we're on and what's actually done.

## Source materials

- `finflow-build-bible-v20.docx` — the book. 31 parts + appendices, organised into
  22 build phases (P0–P22) across 5 Acts.
- `finflow-core.dbml`, `finflow-portal.dbml`, `gateway-simulator.dbml` — the physical
  data model for the three applications (66 / 20 / 13 tables respectively).

## Layout (grows one phase at a time)

- `apps/` — the deployable services (core, portal, simulator, checkout, ...),
  created only when their phase introduces them.
- `docs/` — architecture notes, ADRs (`docs/decisions/`), runbooks, event catalogue.
- `contracts/` — the shared truth across languages: event JSON Schemas, OpenAPI spec.
- `infra/` — Docker and Terraform, kept in step with what's actually deployed.
- `tools/` — seed data, the chaos suite (from Phase 5 onward).

## Running it

Nothing to run yet — this is Phase 0, step 1. Once the core app exists:

```
docker compose -f infra/docker/docker-compose.yml up
```
