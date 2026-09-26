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
| P16 | Hosted Checkout, Payment Methods, 3DS | **done** | yagye_checkout LiveView app + checkout layout builder |

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

- [x] `beneficial_owners` CRUD API: list, add, update, delete UBOs per merchant —
      `GET/POST /merchants/:code/beneficial-owners`, `PUT/DELETE /beneficial-owners/:id`
      via `ComplianceController`.
- [x] 25% UBO ownership threshold guard at `Merchants.approve/2` — `Compliance.ubo_threshold_cleared?(merchant.id)`
      called in `merchants.ex:563` before any KYB approval proceeds.
- [x] AML screening foundation: `screening_subjects` enrolled on merchant creation;
      `GET /merchants/:id/screening-status` and `screening_hits` endpoints live
      via `ComplianceController` (stubbed provider responses OK for now).
- [x] `kyb_documents` metadata upload endpoint — `POST /merchants/:code/documents`
      (`KybController`) + `POST /documents` (`ComplianceController`); stores `kind`,
      `checksum`, `uploaded_by`, returns placeholder `s3_key`. Real S3 presigned URLs
      come at P21.

---

### P4 — Gateway Simulator + Anti-Corruption Layer

- [x] `providers.capabilities` jsonb column migration — added in
      `20260907200001_p16_step0_providers_capabilities.exs` alongside checkout work.

---

### P5 — Failure, Indeterminacy & Transaction Reconciliation

- [x] **Inbound MoMo callback polling/retry** — `StuckPaymentScannerWorker` now recovers
      all three stuck states: `created` (90 s threshold — Oban dispatch job lost before
      the payment was ever sent to the provider; re-enqueues `PaymentDispatchWorker`),
      `processing` (5 min — node crash after state transition; re-enqueues
      `PaymentDispatchWorker`), and `requires_action` (7 min — defensive backstop for a
      dropped `PaymentStatusCheckWorker`; re-enqueues it immediately). The `created`
      recovery closes the "PENDING eternity" gap: if the telecom drops the webhook AND the
      initial dispatch job was lost, the scanner picks it up within 5 min and retries.
      `recover_created_payments/0` in
      `lib/yagye_core/payments/workers/stuck_payment_scanner_worker.ex`;
      5 tests all green.

---

### P6 — Inbound Webhooks, the Inbox & Asynchrony

- [x] Inbox pattern for idempotent telecom callback receipt — `webhook_events` has a
      `unique_constraint([:provider_code, :event_id])`; `WebhookProcessorWorker` uses
      `idempotency_token` as the canonical de-duplication key. An ON CONFLICT on insert
      is the deduplication gate before any payment state transition fires.

---

### P9 — Settlement

- [x] `providers.settlement_cadence` jsonb column migration — added in
      `20260823000005_create_settlement.exs` (`cutoff_hour` int + `cutoff_timezone` text).
- [x] Settlement saga fully wired: `SettlementSchedulerWorker` sweeps eligible payments →
      creates batch → `SettlementProcessorWorker` posts ledger entries (`Ledger.post_batch_approved`)
      → transitions to `settled` → emits `settlement.batch.settled` outbox event →
      enqueues `BankDispatchWorker` → disburses via MoMo or bank transfer → posts
      closing ledger entry → notifies merchant via outbox.
- [x] `SettlementSchedulerWorker` reads `settlement_cadence` per provider (`past_cutoff?/1`
      at line 38) and enqueues `SettlementProcessorWorker` at the correct local cutoff time.

---

### P10 — Reconciliation

- [x] Full automated recon pipeline — `ReconciliationRunWorker` matches Yagye ledger
      entries vs. provider settlement statements automatically; eliminates manual close.
- [x] Exception escalation pathway — unmatched transactions surface as `reconciliation_breaks`
      with severity and state; portal `Payments::ReconciliationController` exposes index
      (with filter by state/severity/date), show, and `propose_adjustment`.
- [x] Human resolution workflow in the portal — ops reviews breaks and proposes adjustments
      via `ReconciliationController#propose_adjustment`; a second ops user approves via
      `Compliance::ApprovalsController#approve_adjustment`. SoD enforced:
      `proposed_by ≠ approved_by` (DB CHECK constraint + changeset guard in place).

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

- [x] SSO/SAML (enterprise-gated): `ruby-saml 1.17` in Gemfile + `SsoConfiguration` model
      + `SsoConfigurationsController` (ops config) + `Users::SsoController` (check/initiate/callback)
      + `Auth::SsoButton` component wired in sign-in view; shown only when
      `SsoConfiguration.active_for_email_domain?(email)` returns true.

---

### P15 — RabbitMQ & Outbound Webhook Delivery

- [x] **Single shared queue design (supersedes per-merchant queue)** — see ADR-0025.
      `yagye.webhooks` (direct exchange) → `yagye.webhooks.delivery` (durable, DLX-configured,
      `x-delivery-limit: 5`) → Broadway `DeliveryPipeline` (concurrency: 10, prefetch: 20).
      Always-ACK strategy: Broadway ACKs every message; retries are driven by Oban
      `WebhookDeliveryRetryWorker` with exponential backoff (10 s / 60 s / 10 min / 1 h),
      never by RabbitMQ requeue. Dead-letters route to `yagye.webhooks.dead_letter` for ops
      inspection. Connection managed by singleton GenServer with auto-reconnect.
- [x] Portal developers/webhooks UI fully wired — `toggle_active` action added to
      `Developers::WebhooksController`; cooldown error surfaced in portal alert.
      `WebhookEventsConsumer` (Karafka) populates delivery log from `webhook.delivery.attempted`
      outbox events via Redpanda.
- [x] **Webhook auto-suspension & cooldown** — 50 consecutive failures → endpoint disabled
      (`active: false`, `disabled_at: now()`). Re-enable blocked for 1 hour after auto-suspension
      (`@reenable_cooldown_seconds 3_600`); API returns HTTP 429 `endpoint_cooldown` with
      `retry_after` ISO 8601 timestamp. Tests: 5 cases covering all cooldown branches.

---

### P16 — Hosted Checkout, Payment Methods, 3DS

- [x] **Step 0 (before any checkout/payment-link code runs):**
      Add RESTRICT FK: `invoices.payment_link_id → payment_links.id on_delete: :restrict`.
      Add `belongs_to :payment_link, PaymentLink` to `Invoice` schema.
      Add `has_many :invoices, Invoice` to `PaymentLink` schema.
      (Column exists in portal DB — nullable, no constraint — safe until P16.)
- [x] **Checkout layout builder (SortableJS/Stimulus)** — merchant drag-and-drop editor
      for payment method ordering, rail visibility, and tile style (compact/expanded) on
      hosted checkout pages. Stimulus + SortableJS (CDN) at `/payment-links/:id/layout`.
      `checkout_layout jsonb` added to `payment_links`. Internal API endpoint:
      `PATCH /internal/payment-links/:id/checkout-layout`. Portal: `Checkout::PaymentLinksController`,
      `checkout_layout_controller.js`, index/form/layout Phlex views, sidebar nav item.
      Enterprise ReactFlow routing-graph entitlement gate deferred to P16.5.

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
