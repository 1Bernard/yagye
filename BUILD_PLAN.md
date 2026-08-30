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

- [ ] TOTP enrolment UI — `Settings::TotpEnrolmentSection`, `Settings::TotpController`,
      QR code via `rqrcode` gem, 8–10 recovery codes stored hashed. Needs
      `otp_secret_encrypted` + `otp_required_for_login` columns (already in DBML).

- [ ] **SoD: ops-managed financial operations** — add DB CHECK constraints + changeset
      guards for:
      - `pricing_rules`: `created_by ≠ approved_by`
      - `settlements` write-off transition: `write_off_initiated_by ≠ write_off_approved_by`
      - `platform_fee_invoices` write-off: same pattern
      (Fields exist in DBML; migrations and guards not yet written.)

---

### P13.5 — Passkeys

- [ ] `devise-passkeys` gem + `create_passkey_credentials` migration
      (uuid PK, `external_id` unique, `public_key`, `sign_count`, `nickname`, `last_used_at`)
- [ ] `Auth::PasskeyButton` + `Settings::PasskeysSection`
- [ ] Stimulus `passkey_controller.js` using `navigator.credentials` API
- [ ] Sign-in page: divider + passkey button below primary "Sign in" button

---

### P14 — Kafka & the Event Backbone

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
