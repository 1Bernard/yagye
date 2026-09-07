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
| P0 | Foundations | **done** | All 8 steps complete. |
| P1 | Merchants, Onboarding & Access | **done** | Merchants, compliance, beneficial owners, KYB docs, idempotency, API keys |
| P2 | The Payment Lifecycle | **done** | Payments context, dispatch worker, provider adapters |
| P3 | The Ledger | **done** | Double-entry accounts, entries, postings, balances |

### Act II — The Distributed Boundary
| Phase | Name | Status | Notes |
|---|---|---|---|
| P4 | Gateway Simulator + Anti-Corruption Layer | **done** | Full simulator app (charges, refunds, outcome engine, webhook delivery, scenarios LiveView) |
| P5 | Failure, Indeterminacy & Transaction Reconciliation | **done** | Bank reconciliation, recon workers |
| P6 | Inbound Webhooks, the Inbox & Asynchrony | **done** | Webhooks context + processor worker |
| P7 | The Outbox, Event Envelope & Projections | **done** | Outbox context + payment summary projections |
| P8 | Observability I | **done** | OpenTelemetry (API, exporter, Phoenix, Ecto, Oban, Req) |

### Act III — The Money Operations
| Phase | Name | Status | Notes |
|---|---|---|---|
| P9 | Settlement | **done** | Settlement batches, scheduler + processor workers |
| P10 | Reconciliation | **done** | Reconciliation context, breaks, workers |
| P11 | Pricing, Fees & Unit Economics | **done** | Pricing context and schemas |
| P12 | Refunds, Disputes, Reserves, Payouts | **done** | All four contexts with workers |

### Act IV — The Product Surface
| Phase | Name | Status | Notes |
|---|---|---|---|
| P13 | The Rails Portal | **done** | Full portal UI, TOTP, SoD, routing graph, team management, role governance |
| P13.5 | Passkeys | **done** | WebAuthn registration + authentication |
| P14 | Kafka & the Event Backbone | **done** | Core Kafka producer (brod 4.6) + outbox relay + topic routing + Portal consumers already built |
| P15 | RabbitMQ & Outbound Webhook Delivery | **done** | amqp 4.2 + broadway_rabbitmq 0.8; yagye.webhooks exchange → delivery queue → Broadway processor → HMAC-signed HTTP POST; outbox relay fans out to endpoints; portal WebhookEventsConsumer already wired |
| P16 | Hosted Checkout, Payment Methods, 3DS | **todo** | |

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
- [x] Step 6 — CI (`.github/workflows/ci.yml`): format, credo, dialyzer, test
- [x] Step 7 — ADR process + first ADRs (0000–0005)
- [x] Step 8 — `mix yagye.schema.export` task wired into CI

Definition of done for P0 (from the book, checked off as we go):
- [x] Repo, compose, ADRs 0000–0024 written
- [x] Money type with conserving allocation and property tests
- [x] JSON logging with correlation ids
- [x] Four test layers wired (unit / property / contract / acceptance)
- [x] `mix yagye.schema.export` wired into CI
- [ ] Budget alarm set (AWS cost guard — deferred to P22 when Terraform touches real AWS)

**What breaks next (per the book):** there is no caller. Anyone can hit the API, and
if a caller retries a request we have no way to avoid creating two payments. That's P1.

---

## Gaps & Deferred Items Backlog

Every identified gap, deferred decision, and cross-phase dependency in one place.
**Check each item off (or explicitly re-defer it with a reason) when its phase begins.**
Do not start a phase without reading its section here first.

---

### Before portal goes live with any real merchant

These four items must exist in `yagye_core` before the portal's compliance view has
integrity. They don't need to be production-grade — stubs are fine — but the endpoints
must exist and return real data shapes.

- [ ] `beneficial_owners` CRUD API: list, add, update UBOs per merchant
- [ ] 25% UBO ownership threshold guard at `Merchants.approve/2` — cannot approve if any
      `beneficial_owner.ownership_bps >= 2500` has an unscreened/uncleared subject
- [ ] AML screening foundation: enrol `screening_subjects` on merchant creation; query
      endpoints for `screening_status` and `screening_hits` (stubbed provider OK)
- [ ] `kyb_documents` metadata upload endpoint — store `kind`, `checksum`, `uploaded_by`,
      return placeholder `s3_key`; real S3 presigned URLs come at P21

---

### P4 — Gateway Simulator + Anti-Corruption Layer

- [ ] `providers.capabilities` jsonb column migration — deferred because routing branching
      only pays off with 2+ providers. Add in P4 Step 1 migration alongside
      `merchant_provider_connections`.

---

### P5 — Failure, Indeterminacy & Transaction Reconciliation

- [ ] **Inbound MoMo callback polling/retry** ← highest-risk unassigned gap.
      When a telecom drops its webhook to Yagye before we receive it, payments sit in
      `initiated` indefinitely even though the customer was debited. This is the root cause
      of the "PENDING eternity" problem Yagye is supposed to eliminate for merchants.
      Definition of done: a worker polls the provider API for payments stuck in `initiated`
      beyond a configurable timeout (e.g. 90 seconds) and transitions them to their true
      terminal state. Must be part of P5's definition of done — not left to P9.

---

### P6 — Inbound Webhooks, the Inbox & Asynchrony

- [ ] Inbox pattern for idempotent telecom callback receipt — deduplicate before any state
      transition so a double-delivered callback from the telecom cannot double-process a
      payment.

---

### P9 — Settlement

- [ ] `providers.settlement_cadence` jsonb column migration — `cutoff_hour` (int, UTC) +
      `cutoff_timezone` (text) per provider; drives `SettlementSchedulerWorker`. Add in
      P9 Step 1 migration alongside `settlement_batches`.
- [ ] Settlement saga fully wired: collect eligible payments → create batch →
      send to bank → confirm receipt → post ledger entries → notify merchant via outbox.
- [ ] `SettlementSchedulerWorker` reads `settlement_cadence` per provider and enqueues
      the sweep at the correct local cutoff time.

---

### P10 — Reconciliation

- [ ] Full automated recon pipeline — eliminates the manual 3-hour daily close.
      Automated matching of Yagye ledger vs. provider settlement statements.
- [ ] Exception escalation pathway — unmatched transactions surface as `reconciliation_breaks`
      requiring human review before the run can be closed.
- [ ] Human resolution workflow in the portal: ops reviews breaks, records disposition,
      closes the run. SoD: `proposed_by ≠ approved_by` on `adjustment_approvals`
      (CHECK constraint + changeset guard already done ✅).

---

### P13 — The Rails Portal

- [x] **Step 0 code gaps — ALL DONE (2026-08-23)**
  - [x] Ledger branches on `provider.kind` — external PSP payments skip settlement entries
  - [x] Settlement sweep filters to `native_rail` providers only
  - [x] Recon trigger guard — skips `start_run` for external PSP batches
  - [x] Credential resolution two-tier lookup (merchant → platform fallback) — was pre-existing

- [x] **Portal UI layer (2026-09-05)**
  - [x] Settings panels: profile (Superform-backed), security, MSISDN allowlists, notifications
  - [x] Phlex form component suite: `Forms::Portal::{Base,Input,Select,Textarea,Checkbox,Field,FieldWrapper}`
  - [x] UI primitives: `UI::PageHeader`, `UI::DetailRow`, `UI::DangerZone`, `UI::Toggle`
  - [x] `Portal::RoleMetadata` model for display-layer role/permission labeling
  - [x] Controllers wired with typed assigns: settings, allowlists, approvals, KYB reviews,
        merchants, disputes, payouts, settlements, transactions, team/users
  - [x] Docker stack fully operational: Core + Portal + Simulator + Redpanda all healthy

- [x] **TOTP enrolment UI (2026-09-05)** — `Account::TotpController` (new/create/recovery_codes/destroy),
      `Settings::TotpSetupView` (QR + manual key + 6-digit verify form), `Settings::TotpRecoveryCodesView`
      (10 codes shown once, copy-all), `Auth::OtpView` (login challenge), `Users::SessionsController`
      intercept + OTP challenge flow. Recovery codes hashed + encrypted at rest. Disable requires
      password confirmation. Security panel shows health score + enable/disable panel.

- [x] **SoD: ops-managed financial operations (2026-09-05)** — DB CHECK constraints added via
      migrations (`pricing_rules_sod`, `settlements_write_off_sod`, `platform_fee_invoices_write_off_sod`);
      changeset guards (`validate_sod/3`, `validate_write_off_sod/1`) in all three schemas.

- [x] **Routing rules editor — Drawflow (2026-09-05)** — ops-only visual graph UI:
      - `Developers::RoutingRulesController` + full CRUD + publish action
      - `Developers::RoutingGraphView` with Drawflow canvas (CDN UMD; Stimulus controller)
      - Closed node vocabulary v1: `ProviderNode`, `ConditionNode`, `SplitNode`, `FallbackNode`
      - Inline embedded form controls per node; no separate properties panel
      - Persisted as `routing_configurations` JSONB via Core's internal API
      - Enterprise merchant variant (entitlement-gated) deferred to P16
      - Note: `compiled_rules` and payment-engine integration deferred (graph stored but not yet evaluated)

---

### P13.5 — Passkeys ✓ (2026-09-05)

- [x] `webauthn` gem (3.4.3) + `create_passkey_credentials` migration
      (uuid PK, `external_id` unique, `public_key`, `sign_count`, `nickname`, `last_used_at`)
- [x] `Settings::PasskeysSection` — enrolled passkey list, hover-reveal delete, "Add passkey" button
- [x] `passkey_controller.js` + `passkey_auth_controller.js` — registration and sign-in Stimulus controllers
- [x] Sign-in page: divider + "Sign in with a passkey" button below primary "Sign in" button
- [x] `Account::PasskeysController` (register_challenge, create, destroy) — Pundit-gated
- [x] `Users::PasskeySessionsController` (challenge, authenticate) — unauthenticated; JSON-based auth
      (avoids Turbo interception of form POST); audit event via `after_sign_in_path_for`
- [x] `PORTAL_ORIGIN` env var drives rpId — set to `http://localhost:3000` in docker-compose
- [x] Double audit-event bug fixed — `after_sign_in_path_for` is the single log site for all sign-in paths

---

### P14 — Kafka & the Event Backbone ✓ (2026-09-06)

Core event backbone complete:
- `brod 4.6` added to `yagye_core` — Kafka/Redpanda client (Erlang, auto-start producers)
- `YagyeCore.Outbox.KafkaProducer` — topic routing (8 topics), hash partitioning by merchant_id,
  flattened envelope + payload merged at top level for consumers
- `YagyeCore.Outbox.KafkaProducer.Stub` — no-op for test env
- `OutboxRelayWorker` updated — dual-dispatch: internal projection workers + Kafka publish on
  every `internal:projections` event; separate `kafka:*` destination clause for Kafka-only events
- Portal consumers (all 8) already fully implemented in earlier session — ready to receive

Redpanda config: `localhost:19092` (dev), `KAFKA_BOOTSTRAP_SERVERS` env (prod), no clients (test).

Remaining P14 items:
- [ ] SSO/SAML (enterprise-gated): `omniauth-saml` + `create_sso_configurations` migration +
      `Settings::SsoSection` (ops config + enterprise merchant config) + `Auth::SsoButton`
      shown only when `SsoConfiguration.active_for_email_domain?(email)` returns true.

---

### P15 — RabbitMQ & Outbound Webhook Delivery

- [ ] Exchange → per-merchant queue (`yagye.webhooks.<merchant_id>`) → consumer POSTs to
      merchant URL → acks on 2xx → nacks + requeues on failure → dead-letters to
      `yagye.webhooks.dead_letter` after max attempts.
- [ ] Wire the portal's developers/webhooks UI (already built) to the live RabbitMQ delivery
      layer here. The `DeliveryDrawerView` and event log table are ready; they just need
      real delivery records from the RabbitMQ consumer.

---

### P16 — Hosted Checkout, Payment Methods, 3DS

- [ ] **Step 0 (before any checkout/payment-link code runs):**
      Add RESTRICT FK: `invoices.payment_link_id → payment_links.id on_delete: :restrict`.
      Add `belongs_to :payment_link, PaymentLink` to `Invoice` schema.
      Add `has_many :invoices, Invoice` to `PaymentLink` schema.
      (Column exists in portal DB — nullable, no constraint — safe until P16.)
- [ ] **Checkout layout builder (dnd-kit)** — merchant drag-and-drop editor for payment
      method ordering, rail visibility, and tile layout on hosted checkout pages.
      Vite + Stimulus + `@dnd-kit/core` mounted at `/checkout/layout`. Layout persists
      as a JSONB column on `payment_links`. Enterprise merchants only get routing graph
      control here (ReactFlow entitlement-gated variant from P13).

---

### P17 — Horizontal Scale & Distributed State

- [ ] Redis for distributed rate limiting — replace in-process ETS rate-limit counters
      with Redis-backed sliding window (key: `rate_limit:{merchant_id}:{window}`)
- [ ] Redis-backed session store for portal (replace cookie store at scale)
- [ ] Horizontal pod autoscaling validation — Core + Portal stateless check,
      Oban queue uniqueness under multi-node (`:global` vs `:local` queue config)
- [ ] Connection pool tuning: PgBouncer or Ecto pool_size review under load

---

### P18 — Observability II: Tracing & SLOs

- [ ] OpenTelemetry collector in docker-compose (Jaeger or Grafana Tempo for local dev)
- [ ] SLO definitions: payment success rate p99 latency, settlement sweep lag,
      reconciliation break mean-time-to-resolution
- [ ] Dashboards: Grafana (or equivalent) wired to OTLP collector
- [ ] Alert rules: settlement stuck > 4h, recon break spike, fraud scorer p95 latency > 50ms

---

### P19 — The Data Platform

- [ ] **Floci in docker-compose** — local AWS S3 + KMS emulator; add to `data` network.
      Provision `yagye-lake-raw` and `yagye-lake-curated` buckets on startup.
- [ ] **Synthetic data generator** — `mix simulator.generate_load` Mix task in
      `gateway_simulator`. Fires N payments at Core API using deterministic MSISDN
      prefixes to produce labeled outcome classes (success / insufficient_funds /
      timeout / fraud-burst). Target: 50k events in < 2 minutes locally.
- [ ] **Redpanda → Parquet sink** — Redpanda Connect pipeline consuming outbox topics
      (`payment.*`, `dispute.*`, `reconciliation.*`) and writing partitioned Parquet to
      Floci S3: `s3://yagye-lake-raw/events/year=YYYY/month=MM/day=DD/`.
- [ ] **DuckDB feature extraction layer** — Python notebook + scripts querying Floci S3
      directly (`SET s3_endpoint='floci:4566'`). Computes: inter-arrival times,
      provider success rates by 15-min window, merchant baseline deviation, T+1 drift stats.
- [ ] See ADR-0022 for architecture decisions.

---

### P20 — Risk & Machine Learning

- [ ] **Scoring service** (`apps/yagye_scoring`) — FastAPI + Uvicorn container on
      `core_mesh` network. Loads `.onnx` model weights. Exposes:
      - `POST /score/routing` → `{provider_scores: [{provider_code, score}]}`
      - `POST /score/risk` → `{risk_score: float, signals: [...]}`
      Fallback: if service unreachable, Core falls back to rule-based routing.
- [ ] **Model 1 — Smart routing predictor** — LightGBM trained on P19 Parquet data.
      Features: provider, network, amount_bucket, hour_of_day, recent_error_rate (15m window).
      Target: P(success). Replaces static provider priority in `PaymentDispatchWorker`.
- [ ] **Model 2 — MoMo velocity & burst anomaly scorer** — time-series anomaly model
      on inter-arrival times, hour-of-day, amount deviation from merchant baseline.
      Plugs into `VelocityChecker` — scores > 0.85 → `:hold` instead of `:ok`.
- [ ] **Model 3 — Reconciliation break classifier** — trained on historical break types.
      Classifies: T+1 timing lag / fee schedule drift / dropped webhook / true shortfall.
      Auto-generates compensating posting suggestion for confidence > 0.99.
      Plugs into `Reconciliation.classify_break/1`.
- [ ] **Model 4 — Dynamic rolling reserve predictor** — predicts 90-day dispute probability
      per merchant. Replaces flat reserve percentage in `YagyeCore.Reserves.compute_rate/1`.
- [ ] See ADR-0023 for ML scoring architecture decisions.

---

### P21 — Security Hardening

- [ ] S3 + KMS for KYB documents — replace placeholder `s3_key` from the metadata endpoint
      with real presigned upload/download URLs via AWS S3 + KMS encryption.
- [ ] `screening_hits` SoD: add DB CHECK `raised_by IS NULL OR dispositioned_by IS NULL OR
      raised_by ≠ dispositioned_by` + `validate_sod/1` in `ScreeningHit.disposition_changeset/2`.
      (DBML already updated; migration deferred.)
- [ ] `merchants` SoD DB CHECK: add `CHECK (reviewed_by IS NULL OR approved_by IS NULL OR
      reviewed_by ≠ approved_by)` migration. Changeset guard already exists — this adds
      the DB-level backstop.
- [ ] Ghana Registrar General (RGD) registry check integration — verify business registration,
      directors, good standing via RGD API.
- [ ] Full AML provider integration (ComplyAdvantage or LexisNexis) — replace screening stubs
      with real API calls.

---

### Permanently deferred

| Item | Decision |
|---|---|
| Commanded / Event Store (CQRS/ES) | Replaced by saga state-row + Oban workers per phase |
| Pre-approval fast-track allowlist (portal) | Product decision needed before building |
| Network blocklist (portal) | Product decision needed before building |
| KYC session reuse across companies | Not planned — `subject_ref → pii_vault` supports it technically if needed |
| Signature integrity on KYB documents | Delegate to Onfido/Veriff — not Yagye's responsibility |
| Device/IP risk scoring (Sardine/Seon/Kount) | Not planned for initial launch |

---

### Pending business decisions (do not build until resolved)

- **Large refund SoD threshold**: refunds above a threshold may need a two-person rule
  (initiator ≠ approver). The `adjustment_approvals` pattern is the model. Do NOT add
  until the business has set a threshold — premature SoD on all refunds creates
  operational friction for small merchants.
