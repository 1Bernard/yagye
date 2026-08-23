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
| P0 | Foundations | **in-progress** | Steps 1–6 done. Steps 7–8 (ADRs 0000–0005, schema export task) deferred — picked up during P1. |
| P1 | Merchants, Onboarding & Access | **done** | 102 tests, 0 failures. Phase gate: `OnboardingJourneyTest`. |
| P2 | The Payment Lifecycle | **done** | Oban wired; payments + payment_attempts + payment_events; dispatch worker; simulator adapter + ProviderAdapter behaviour. |
| P3 | The Ledger | **done** | Double-entry ledger: accounts, entries, postings, balances. |

### Act II — The Distributed Boundary
| Phase | Name | Status |
|---|---|---|
| P4 | Gateway Simulator + Anti-Corruption Layer | **done** | Simulator app (charges, refunds, scenarios, name enquiry, wallet prompts); providers, provider_credentials, merchant_provider_connections in core; ProviderAdapter behaviour + SimulatorAdapter. |
| P5 | Failure, Indeterminacy & Transaction Reconciliation | **done** | Disputes and refunds context; dispute + refund schemas, events, controllers, OpenAPI specs. |
| P6 | Inbound Webhooks, the Inbox & Asynchrony | **done** | WebhookDeliveryWorker (simulator, HMAC-SHA256 signed); webhook_events inbox + WebhookProcessorWorker (core); PENDING_AUTH → requires_action state; Providers.get_webhook_secret/1. |
| P7 | The Outbox, Event Envelope & Projections | **done** | outbox_messages + EventEnvelope + OutboxRelayWorker; projection workers (PaymentSummary version fence, MerchantBalance dedup, DailyMetrics hourly recompute); all three domain contexts migrated to Ecto.Multi; outbox wired in payments, merchants, disputes; ledger-reversal bug fixed in disputes. |
| P8 | Observability I | **done** | OTel SDK + auto-instrumentation (Phoenix, Ecto, Oban); manual spans on dispatch, ledger, outcome engine; trace_id on payment_events. |

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
| P21b | AML / PEP Screening | todo |
| P22 | Going Live | todo |

## Phase 0 — step-by-step log

- [x] Step 1 — empty repo skeleton (`docs/`, `contracts/`, `apps/`, `infra/`, `tools/`),
      README, this file, git initialised. No code yet.
- [x] Step 2 — Elixir project boots (`apps/yagye_core`, `mix phx.new`, deps installed,
      `mix test` runs green on nothing — 2 tests, 0 failures)
- [x] Step 3 — `Yagye.Money` type + allocation property test (6 properties, 17 tests, 0 failures)
- [x] Step 4 — structured JSON logging with correlation ids (logger_json 7.0, Basic formatter, CorrelationId plug)
- [x] Step 5 — Dockerfile + docker-compose.yml (Postgres only, multi-stage build verified)
- [x] Step 6 — CI (`.github/workflows/ci.yml`): format, credo, dialyzer, test
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

## Phase 1 — what was built

- Merchants: create, approve, get (with public_id / prefixed UUIDv7)
- API keys: issue, list, revoke (soft delete) — argon2 hash, bearer auth, mode-aware, scoped
- Idempotency: PostgreSQL-backed state machine (in_progress → completed | failed)
- Rate limiting: ETS-backed token bucket (per API key, node-local)
- KYB / compliance: submit onboarding details, add beneficial owner, upload document
- OpenAPI: full spec, SwaggerUI, CastAndValidate on all endpoints
- ADRs: 0000–0011 written and accurate
- Contract: `contracts/openapi/yagye-core.json` exported
- Tests: 8 properties, 102 tests — unit, integration, phase gate (onboarding journey)

New library introduced: `open_api_spex` (OpenAPI spec + request validation).

**What breaks next:** merchants can now be onboarded, but there is nothing to pay with.
P2 introduces the payment lifecycle — payment intents, state machine, and the first
background job processor. New library: **Oban**.

## Phase 2 — what was built

- Oban dep + `oban_jobs` table migration, wired into supervision tree
- Payment intent creation with prefixed UUIDv7 public_id
- `payment_attempts` — per-attempt state machine (pending → dispatched → succeeded/failed/timed_out)
- `payment_events` — append-only log per payment
- `PaymentDispatchWorker` (Oban) — picks up intents, calls ProviderAdapter, writes attempt outcome
- `ProviderAdapter` behaviour + `SimulatorAdapter` (the anti-corruption adapter)
- Full OpenAPI spec + CastAndValidate for payment endpoints

## Phase 3 — what was built

- Double-entry ledger: `accounts`, `entries`, `postings`, `balances`
- `Ledger` context with `post/1` — accepts a posting (credit + debit pair), validates balanced entries, inserts atomically
- `YagyeCore.Shared.Money` allocation used throughout (conserving, integer minor units)

## Phase 4 — what was built

- `yagye_simulator` app: accounts, charges, refunds, scenarios, name enquiry, wallet prompts
- `providers`, `provider_credentials`, `merchant_provider_connections` tables in core
- `ProviderAdapter` behaviour in core; `SimulatorAdapter` translates domain calls to simulator API
- Simulator: `OutcomeEngine` drives probabilistic charge outcomes via scenario rates
- Simulator: LiveView `ScenarioLive` (chaos control UI, started)
- Structured JSON logging with correlation IDs in both apps

## Phase 5 — what was built

- `disputes` and `refunds` contexts in core
- Dispute + refund schemas, event structs, commands
- REST controllers, JSON views, OpenAPI specs for disputes and refunds
- Integration with payments: refund validates against original payment amount

## Phase 6 — step-by-step log

- [x] Step 1 — `webhook_notification` schema in simulator (placeholder struct)
- [x] Step 2 — outgoing webhook delivery from simulator to core (HTTP POST with HMAC-SHA256 signature)
- [x] Step 3 — inbound webhook inbox in core: idempotent receipt, signature verification, Oban enqueue
- [x] Step 4 — `WebhookProcessorWorker` in core: routes by event_type to domain handlers

## Phase 7 — step-by-step log

- [x] Step 1 — migration: `outbox_messages` + three projection tables + `providers.kind` column
- [x] Step 2 — Ecto schemas for all four tables + `EventEnvelope` struct
- [x] Step 3 — `YagyeCore.Events.emit/3` — atomic outbox write inside caller's transaction
- [x] Step 4 — `OutboxRelayWorker` (Oban cron + self-reschedule) — reads undelivered rows, dispatches projection workers
- [x] Step 5 — `PaymentSummaryProjection` worker (version fencing)
- [x] Step 6 — `MerchantBalanceProjection` worker (event dedup on event_id)
- [x] Step 7 — `DailyMetricsWorker` (hourly recompute from source)
- [x] Step 8 — `payments.ex` emits outbox events on created/authorised/succeeded/failed/indeterminate
- [x] Step 9 — tests: outbox emission atomicity, payload integrity, idempotency, version fencing (11 tests)

## Phase 9 — step-by-step log

Scope: accounting-only settlement — batch succeeded payments per merchant+currency,
post ledger entries, no fee deduction (P11) and no bank transfer (P12).

Ledger move: Debit `merchant_payable` → Credit `settlement_approved` (committed, pending disbursement).

Saga pattern: no saga framework — state-row (`settlement_batches.state`) + Oban workers +
compensating action on failure (mark batch failed, leave payments unsettled for next cycle).

Deferred items landing here:
  - `providers.settlement_cadence` jsonb column (cutoff hour + timezone) — deferred from P4 schema design
  - `adjustment_approvals.CHECK (approved_by <> proposed_by)` SoD constraint — deferred from P5;
    add in this migration so reconciliation (P10) inherits the guard from day one

- [ ] Step 1 — migration: `settlement_batches` table; `settlement_batch_id` FK on `payments`;
               `providers.settlement_cadence` jsonb column
               (SoD CHECK on `adjustment_approvals` moves to P10 Step 1 — table doesn't exist yet)
- [ ] Step 2 — `SettlementBatch` schema + update `Payment` schema with `settlement_batch_id`
- [ ] Step 3 — `Settlement` context: `create_batch/2` sweeps unsettled succeeded payments for a
               merchant+currency into a new pending batch (idempotent guard: no open batch already exists)
- [ ] Step 4 — `Ledger.post_batch_approved/2` — Debit `merchant_payable`, Credit `settlement_approved`,
               both scoped to merchant; called atomically inside the batch processor transaction
- [ ] Step 5 — `SettlementProcessorWorker` (Oban, queue: `:settlement`) — transitions batch
               `pending → processing → settled`; posts ledger entry; stamps `settlement_batch_id` on
               each payment; emits outbox events; idempotent via batch state guard
- [ ] Step 6 — `SettlementSchedulerWorker` (Oban cron, daily) — fans out one `SettlementProcessorWorker`
               per merchant+currency with unsettled payments; respects `provider.settlement_cadence` cutoff
- [ ] Step 7 — outbox events: `settlement.batch.created`, `settlement.batch.settled` (wired into
               existing `OutboxRelayWorker`)
- [ ] Step 8 — tests: batch creation, ledger balance assertions, idempotency (no double-batch),
               scheduler fanout, outbox emission

## Phase P21b — AML / PEP Screening

**Prerequisite:** Outbox infrastructure (P7), Compliance context (P1), Portal ops queue (P13).
**Must be complete before P22 (Going Live).**

Scope: Full global-standard AML/PEP screening for merchants and their beneficial owners.
Screening is abstracted like payment providers — a `ScreeningAdapter` behaviour, a
`StubScreeningAdapter` for test/simulation, and real provider adapters (Comply Advantage
first) dropped in without touching domain logic.

### Why three tables

`screening_subjects` — enrolment and ongoing schedule. One row per subject; survives
across many screening runs. The scheduler reads `next_screening_at` to know who is due.

`screening_requests` — immutable audit evidence. One row per API call regardless of
outcome. A failed request is retried by creating a NEW row, never mutating the old one.
The regulator will ask: "did you check, when, against which lists, using which provider,
and what did they say?" This table answers that.

`screening_hits` — individual matches above the confidence threshold. Enhanced with
`pep_tier` (1/2/3), `rca_relationship` (Relatives and Close Associates), and
`screening_request_id` FK. RCA hits carry the same EDD obligation as direct PEP hits
under FATF Recommendation 12.

### Step-by-step

- [ ] Step 1 — migration: `screening_providers`, `screening_subjects`, `screening_requests`;
               add `screening_request_id`, `pep_tier`, `rca_relationship` to `screening_hits`
- [ ] Step 2 — `ScreeningProvider` schema; `ScreeningSubject` schema; `ScreeningRequest` schema;
               update `ScreeningHit` schema with new fields
- [ ] Step 3 — `ScreeningAdapter` behaviour:
               `screen(subject_attrs, lists) :: {:ok, [match]} | {:error, reason}`
               `StubScreeningAdapter` — returns configurable fixture matches for test/simulation
- [ ] Step 4 — `Compliance.enrol_subject/2` — creates a `screening_subject` row; idempotent
               on (subject_type, subject_id). Called from `add_beneficial_owner` and
               `submit_onboarding` (merchant entity screening).
- [ ] Step 5 — `ScreeningWorker` (Oban, queue: `:compliance`) — consumes
               `compliance.beneficial_owner_added` and `compliance.onboarding_submitted` outbox
               events; creates a `screening_request`; calls the adapter; stores hits; updates
               `screening_subject.screening_status` and `next_screening_at`; emits
               `compliance.screening_hit_raised` for each hit above threshold
- [ ] Step 6 — `ScreeningSchedulerWorker` (Oban cron, daily) — queries `screening_subjects`
               WHERE `next_screening_at <= now()` AND status not blocked/suspended; enqueues
               one `ScreeningWorker` per subject with trigger: `periodic`
- [ ] Step 7 — Disposition enforcement: `true_match_blocked` on a sanctions hit must set
               `merchant.status = suspended` atomically (same Multi); no code path to reverse
               without a compliance officer action in the portal
- [ ] Step 8 — PEP EDD flag: `confirmed_pep` status sets a flag on the merchant record
               (`merchants.risk_rating = high`) and raises an ops portal alert; does NOT block
- [ ] Step 9 — tests: first-screen on onboarding, periodic rescreen scheduling, PEP tier
               propagation, sanctions block propagation, RCA hit stored correctly, idempotency
               (duplicate search_ref deduped), StubScreeningAdapter fixture scenarios

### Sanctions lists checked by default (global minimum)
| List | Issuer | Coverage |
|---|---|---|
| OFAC SDN | US Treasury | US-nexus transactions, all USD |
| EU Consolidated | European Union | EU-nexus |
| UN Security Council | United Nations | Universal |
| UK HMT/OFSI | UK Treasury | UK-nexus |
| BoG Watch List | Bank of Ghana | Ghana-specific, domestic requirement |

### PEP tier reference
| Tier | Examples | EDD intensity |
|---|---|---|
| 1 | Heads of state, government ministers, senior military/judiciary/central bank officials | Highest — senior sign-off required |
| 2 | Members of parliament, ambassadors, senior state-owned enterprise executives | High — compliance officer sign-off |
| 3 | Local/regional officials, lower government | Standard EDD |
| RCA | Spouse, child, parent, sibling, close associate of any tier | Same as the PEP they are associated with |
