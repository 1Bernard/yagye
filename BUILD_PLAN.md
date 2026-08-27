# Yagye — Build Plan

This is the single source of truth for where we are. Update it every time a phase
step is completed or a decision is made. Status values: `todo`, `in-progress`, `done`.

## How we're working

- One phase at a time, in order (P0 → P22). Each phase is broken into small,
  visible steps — no batch work you haven't seen.
- Every step is built, then proven (test/demo), before moving to the next.
- Decisions get an ADR in `docs/decisions/` the day they're made — see the log below
  for ones already made in conversation, to be written up as ADRs as we reach them.

## Tooling & infra decisions made so far

| Decision | What | When it actually matters |
|---|---|---|
| Local AWS emulation | [Floci](https://github.com/floci-io/floci) instead of real AWS or LocalStack Community — MIT, no auth token, broader service coverage via real Docker backends (RDS, ElastiCache, MSK, Glue/Athena, Secrets Manager, KMS, ECR, S3, ...) | Not needed for P0–P8 (just Postgres in Compose). Starts mattering at P0 (ECR for the Terraform skeleton), grows through P17 (ElastiCache), P19 (S3 lake, Glue, Athena, MSK Connect), P21 (Secrets Manager, KMS). Real AWS only enters at P22. |
| Elixir project layout | Poncho (independent `mix.exs` per deployable app + `path:` deps), not umbrella | From P0 |
| Ledger money type | Hand-rolled `FinFlow.Money` (integer minor units + allocation), not `ex_money` | P0 |
| Rate limiting | ETS (node-local) until P17, then Redis | P1 → P17 |
| DB per app | `yagye_core`, `yagye_portal`, `gateway_simulator` are three separate Postgres databases, never shared | From P1 (core), P4 (simulator), P13 (portal) |

## Phase status

### Act I — The Correct Core
| Phase | Name | Status | Notes |
|---|---|---|---|
| P0 | Foundations | **in-progress** | Step 1 (empty repo skeleton) done. Next: Elixir project boots. |
| P1 | Merchants, Onboarding & Access | todo | |
| P2 | The Payment Lifecycle | todo | |
| P3 | The Ledger | todo | |

### Act II — The Distributed Boundary
| Phase | Name | Status |
|---|---|---|
| P4 | Gateway Simulator + Anti-Corruption Layer | todo |
| P5 | Failure, Indeterminacy & Transaction Reconciliation | todo |
| P6 | Inbound Webhooks, the Inbox & Asynchrony | todo |
| P7 | The Outbox, Event Envelope & Projections | todo |
| P8 | Observability I | todo |

### Act III — The Money Operations
| Phase | Name | Status |
|---|---|---|
| P9 | Settlement | todo |
| P10 | Reconciliation | todo |
| P11 | Pricing, Fees & Unit Economics | todo |
| P12 | Refunds, Disputes, Reserves, Payouts | todo |

### Act IV — The Product Surface
| Phase | Name | Status |
|---|---|---|
| P13 | The Rails Portal | todo |
| P14 | Kafka & the Event Backbone | todo |
| P15 | RabbitMQ & Outbound Webhook Delivery | todo |
| P16 | Hosted Checkout, Payment Methods, 3DS | todo |

### Act V — Scale, Data, Risk, Real Money
| Phase | Name | Status |
|---|---|---|
| P17 | Horizontal Scale & Distributed State | todo |
| P18 | Observability II: Tracing & SLOs | todo |
| P19 | The Data Platform | todo |
| P20 | Risk & Machine Learning | todo |
| P21 | Security Hardening | todo |
| P22 | Going Live | todo |

## Phase 0 — step-by-step log

- [x] Step 1 — empty repo skeleton (`docs/`, `contracts/`, `apps/`, `infra/`, `tools/`),
      README, this file, git initialised. No code yet.
- [x] Step 2 — Elixir project boots (`apps/yagye_core`, `mix phx.new`, deps installed,
      `mix test` runs green on nothing — 2 tests, 0 failures)
- [x] Step 3 — `Yagye.Money` type + allocation property test (6 properties, 17 tests, 0 failures)
- [x] Step 4 — structured JSON logging with correlation ids (logger_json 7.0, Basic formatter, CorrelationId plug)
- [x] Step 5 — Dockerfile + docker-compose.yml (Postgres only, multi-stage build verified)
- [ ] Step 6 — CI (`.github/workflows/ci.yml`): format, credo, dialyzer, test
- [ ] Step 7 — ADR process + first ADRs (0000–0005)
- [ ] Step 8 — `mix yagye.schema.export` task wired into CI

Definition of done for P0 (from the book, checked off as we go):
- [ ] Repo, compose, ADRs 0000–0005 written
- [ ] Money type with conserving allocation and property tests
- [ ] JSON logging with correlation ids
- [ ] Four test layers wired (unit / property / contract / acceptance)
- [ ] `mix yagye.schema.export` wired into CI
- [ ] Budget alarm set (AWS cost guard — comes later once Terraform touches real AWS)

**What breaks next (per the book):** there is no caller. Anyone can hit the API, and
if a caller retries a request we have no way to avoid creating two payments. That's P1.
