# Remaining Features — Build Catalog

**Last updated:** 2026-11-22 (P19 done; P20 done; §0.4, §0.6, §0.7, §1.1–1.5 built; portal risk section built; Models 1 & 4 trained)

Every feature that is documented in the DBML but not yet migrated or built.
For each feature: what it is, why it matters in a PSP context, the phase it
belongs to, what must exist first, and how to implement it.

The `// DEFERRED:` comment in `docs/schema/yagye-portal.dbml` or
`docs/schema/yagye-core.dbml` is the single canonical phase tag per table.
This document adds the engineering context that the DBML cannot carry.

---

## 0. Pre-Launch Gaps — Must Fix Before First Real Merchant

These are not deferred features. They are gaps in the current implementation
that block going live with real money or real merchants. Everything in
sections 1–6 below is correctly deferred. These are not.

---

### 0.1 KMS Envelope Encryption for KYB Documents — **BLOCKER**

**What is missing**
`ex_aws_kms` is not in `apps/yagye_core/mix.exs`. Config has
`kms_key_arn: nil`. KYB documents currently land in S3 with SSE-S3
(server-side encryption managed by S3), not SSE-KMS with per-document
envelope keys. The DBML contract (`kyb_documents.s3_key`) specifies
`[SEC] SSE-KMS, private, presigned access only`. Without per-document
envelope keys, the crypto-shredding model (destroy the KMS key to erase
a subject's data) cannot work, and you cannot demonstrate per-document
access revocation to auditors.

**Fix**
1. Add to `apps/yagye_core/mix.exs`: `{:ex_aws_kms, "~> 2.4"}`
2. In `DocumentStore.presign_upload/4`, add headers:
   `"x-amz-server-side-encryption": "aws:kms"` and
   `"x-amz-server-side-encryption-aws-kms-key-id": kms_key_arn`
3. Set `config :yagye_core, :document_store, kms_key_arn: System.get_env("KYB_KMS_KEY_ARN")` in `config/runtime.exs`
4. Provision the KMS key in Floci for local dev, real KMS for prod

**Effort** — 2–4 hours

---

### 0.2 AML Provider — Flip from Stub — **BLOCKER**

**What is missing**
`config :yagye_core, :aml_provider, YagyeCore.Compliance.AmlProvider.Stub`
is active in every environment. The `ComplyAdvantage` adapter
(`apps/yagye_core/lib/yagye_core/compliance/aml_provider/comply_advantage.ex`)
is fully implemented and tested. With the stub active, no real sanctions
screening runs against any merchant, beneficial owner, or director during
onboarding. This means you are onboarding merchants without AML checks.

**Provider choice**
ComplyAdvantage is the industry-standard AML provider for fintechs and PSPs
(used by Revolut, Monzo, and most licensed neobanks). It covers OFAC SDN, EU
Consolidated, UN Security Council, UK HMT/OFSI, PEP tiers 1–3, RCAs, and
adverse media — the full set required for BoG licensing.

**Cost — no credit card needed at launch**
ComplyAdvantage offers **ComplyLaunch**: free for 12 months for early-stage
startups that have not previously partnered with ComplyAdvantage and have a
company website. This covers the entire pre-launch and first year of live
operation. After 12 months:
- Up to 100 monitored entities: $99/month (annual billing)
- Up to 500 monitored entities: $199/month
- Up to 2,000 monitored entities: $319/month

Apply at: `complyadvantage.com/complylaunch/`

**Fix**
1. Apply for ComplyLaunch at `complyadvantage.com/complylaunch/` and obtain
   an API key. No credit card is required for the startup program.
2. Add the API key to Secrets Manager (or `.env` for local prod testing):
   `COMPLY_ADVANTAGE_API_KEY=<key>`
3. The runtime.exs config flip is already in place — `AML_PROVIDER_MODULE`
   defaults to `YagyeCore.Compliance.AmlProvider.ComplyAdvantage` in prod.
   No code change is required. The adapter is complete.

**Effort** — 30 minutes of code work + ComplyLaunch application review time
(typically 1–3 business days)

---

### 0.3 Production Infrastructure (Terraform) — **BLOCKER**

**What is missing**
`infra/terraform/main.tf` has only `ecr.tf` stubs. No ECS task definitions,
ALB, managed RDS, managed ElastiCache, MSK (Redpanda), or Secrets Manager
wiring exists in Terraform. The data platform ETL currently runs as
`while true; sleep 3600` inside a docker-compose service, which must not
reach production.

**Fix** — This is the full P22 infrastructure sprint:
- ECS task definition per service (yagye_core, yagye_portal, gateway_simulator
  dev-only, scoring_service, Redpanda, Redis, Grafana stack)
- ALB with target groups: port 4000 (Core API), port 3000 (Portal), port 8080
  (scoring service)
- Managed RDS PostgreSQL (Multi-AZ for the core DB at launch)
- Managed ElastiCache Redis (rate limiting + portal sessions)
- Secrets Manager entries for all credentials (AML API key, provider
  credentials, portal secret_key_base, etc.)
- Real S3 buckets replacing Floci endpoints (update `AWS_ENDPOINT_URL` in
  runtime.exs to be absent in production, falling back to real AWS)
- EventBridge Scheduler replacing the docker-compose ETL cron
- VPC, security groups, IAM roles

**Effort** — 2–3 day infrastructure sprint

**Note** — See `docs/architecture/scaling-playbook.md` for guidance on when
to add a second node to each service and what load balancer configuration
each service requires.

---

### ~~0.4 `outbox_messages` Cleanup Worker~~ — **DONE**

`OutboxCleanupWorker` exists at `apps/yagye_core/lib/yagye_core/outbox/workers/outbox_cleanup_worker.ex`.
Runs nightly via Oban crontab (`0 2 * * *`), purges published rows older than 7 days.

---

### 0.5 `routing_native_rail` Model — Upload to S3 — Before First Merchant

**What is missing**
The model is trained. The ONNX file exists in the local MLflow artifact
store. The S3 upload failed during training because Floci was not running
at that time. No `champion.flag` exists in S3 for any model, so the scoring
service falls back to rule-based predictions for all 4 models (including
routing, which has a real trained model available).

**Fix**
```bash
docker compose up floci -d
python apps/yagye_data/scripts/train_models.py --model routing_predictor
```
Then restart the scoring service. It reads `champion.flag` from S3 at
startup and will begin serving real routing predictions.

The other three models (`risk_scorer`, `reserve_recommender`,
`churn_predictor`) correctly remain on rule-based fallback — they were
skipped during training due to insufficient Silver data. They will be trained
after 4–6 weeks of live transaction history accumulates.

**Effort** — 1 hour

---

### ~~0.6 Silver Data Quality Checks~~ — **DONE**

`apps/yagye_data/src/yagye_data/shared/silver_quality.py` implements `emit()`: logs
`source_rows`, `output_rows`, `dropped_rows`, and `null_amount_count` at WARNING level
(Loki alert fires on `dropped_rows > 0` or `null_amount_count > 0`). Called after each
Silver COPY in the ETL pipeline.

---

### ~~0.7 Escrow Auto-Release Scheduling~~ — **DONE**

`Escrow.create_hold/3` schedules `EscrowAutoReleaseWorker` with `scheduled_at: hold.auto_release_at`
at lines 71-72 of `apps/yagye_core/lib/yagye_core/escrow/escrow.ex`. Verified.

---

### Summary Table

| Gap | Severity | Effort | Act when |
|---|---|---|---|
| 0.1 KMS for KYB documents | Blocker | 2–4 h | Before first KYB upload |
| 0.2 AML provider from stub | Blocker | 30 min + ComplyLaunch review (1–3 days) | Before first merchant onboarding |
| 0.3 Production Terraform | Blocker | 2–3 days | Before deploying to real AWS |
| ~~0.4 outbox_messages cleanup~~ | ~~High~~ | **Done** | — |
| 0.5 routing model S3 upload | High | 1 h | Before first merchant goes live |
| ~~0.6 Silver data quality checks~~ | ~~High~~ | **Done** | — |
| ~~0.7 Escrow auto-release verify~~ | ~~High~~ | **Done** | — |

There is also one fix that is not needed for single-node launch but must be
applied before the second Core node is added: the settlement batch race
condition handler in `settlement.ex`. See
`docs/architecture/scaling-playbook.md § 2e` for details.

---

## 1. ~~Ready Now (Unblocked)~~ — **ALL BUILT**

All five items in this section were built during P13/P13.5:

| Item | What was built |
|---|---|
| ~~1.1 `user_sessions`~~ | Model, migration, Devise override for sign-in/sign-out, security settings page |
| ~~1.2 `saved_filters`~~ | Model, migration, filter persistence per namespace |
| ~~1.3 `processed_events`~~ | Model, migration, `IdempotentConsumer` concern, `ProcessedEventSweepJob` (30-day purge) |
| ~~1.4 `portal_merchant_balances`~~ | Model, `PaymentEventsConsumer` + `SettlementEventsConsumer` projecting balances, dashboard read |
| ~~1.5 `portal_daily_metrics`~~ | Model, migration, `PortalDailyMetricsRecomputeJob` (hourly Solid Queue cron) |

---

## 2. Near-Term (P14–P16)

These features require infrastructure or Core logic not yet built, but are
on the immediate horizon.

---

### 2.1 `portal_refunds` — Refund Management UI

**What it is**
A portal read model and UI for tracking merchant-initiated refunds. Merchants
can initiate a refund on a succeeded payment; the portal records the refund's
lifecycle (`requested → processing → succeeded | failed`).

**Why it matters**
Refunds are a routine merchant operation. Without a UI, merchants must track
refund state via webhooks or API polling — unacceptable for a portal that is
meant to be the merchant's primary operational interface.

**PSP relevance**
Refund processing speed and visibility is a key PSP quality metric. Merchants
who cannot see their refund status in the portal escalate to support. The
`portal_refunds` table also gives compliance teams a searchable audit trail of
all reversals.

**Phase** — P16

**Prerequisites** — Refund API endpoint must exist in Core (`POST
/v1/payments/:id/refund`). Core must emit `refund.requested`,
`refund.processing`, `refund.succeeded`, `refund.failed` events via the outbox.
`fee_records.reversal_of_id` (already in the schema) must be populated by the
Core refund flow.

**Implementation approach**

- **Core (Elixir):** Build the refund domain logic: state machine, ledger
  reversal entries, fee reversal, outbox events. The provider adapter must
  support a `refund/2` callback.
- **Portal (Rails):** Migration for `portal_refunds`. Karafka consumer
  projecting refund events. UI: a "Refund" button on the payment detail drawer,
  a confirmation modal with amount and reason, a refunds sub-tab on the payments
  page.
- **Simulator:** The gateway_simulator must support `POST /refund` per adapter.
  Return `refund_id` in the response. Simulate both success and failure
  outcomes via `X-Simulator-Outcome`.

**Complexity** — High. Requires Core domain logic, provider adapter changes,
ledger reversal, and full portal UI.

---

### 2.2 `portal_provider_connections` — Orchestration Console

**What it is**
A portal UI for enterprise merchants (Model B) to view and manage their
connections to external PSP providers. Shows each connection's status
(`active | paused | disabled`), health state from Core's circuit breaker,
enabled payment methods, and credential expiry. Gated by an entitlement.

**Why it matters**
Enterprise merchants using Yagye's orchestration layer need operational
visibility into their provider connections. A paused connection means no
payments routing to that provider. A credential expiring silently means a
live outage with no warning.

**PSP relevance**
This is the Model B (orchestration) portal surface. Without it, enterprise
onboarding requires manual ops intervention for every connection change.
The `credential_expires_at` warning banner (shown within 14 days) is a
proactive reliability feature — preventing the silent expiry outages that are
a common PSP horror story.

**Phase** — P14+

**Prerequisites** — Redpanda is live (P14). The `merchant_provider_connections`
table exists in Core. Core emits `provider_connection.*` events via the outbox.
Enterprise merchant entitlement exists in the RBAC system.

**Implementation approach**

- **Core (Elixir):** Build the `merchant_provider_connections` table and
  context. Emit events on connection status changes and credential updates.
  The circuit breaker must update `health_state` on every provider call
  outcome.
- **Portal (Rails):** Migration for `portal_provider_connections`. Karafka
  consumer projecting connection events. UI: a "Providers" section under
  developer/settings, visible only to enterprise merchants. Health state badge
  with Turbo Stream broadcast on change.

**Complexity** — High. Requires Core domain logic, circuit breaker integration,
and portal entitlement gating.

---

## 3. Compliance & KYB (P21)

These features are blocked on S3/KMS infrastructure (Floci for local
simulation, real AWS at P22).

---

### 3.1 `portal_kyb_documents` — Document Review Queue

**What it is**
An ops-facing queue of KYB documents uploaded by merchants during onboarding.
The portal shows document metadata (kind, upload date, virus scan status);
clicking through issues a presigned S3 URL from Core so the ops analyst can
view the actual document without the file passing through the portal.

**Why it matters**
Compliance teams cannot approve a merchant without reviewing their documents.
Without this table, document review requires direct S3 console access — not
auditable, not role-restricted, not scalable.

**PSP relevance**
Document review is on the KYB critical path. A slow or manual document review
workflow is a direct bottleneck on merchant activation time. The `scanned_at`
column (null = not yet virus-scanned) enforces a security gate: ops cannot
view a document until it has been scanned.

**Phase** — P21b

**Prerequisites** — S3 and KMS in Floci (local) and real AWS (prod). Core
must have a `kyb_documents` table and emit `kyb.document.uploaded` events.
Core must expose a `/internal/kyb-documents/:id/presigned-url` endpoint.

**Implementation approach**

- **Core (Elixir):** `kyb_documents` context: accept multipart upload, stream
  to S3, record metadata, trigger async virus scan, emit outbox event.
- **Portal (Rails):** Migration for `portal_kyb_documents`. Consumer projecting
  `kyb.document.*` events. UI: document cards in the merchant KYB drawer, each
  with a "View" link that calls Core for a presigned URL.
- **Floci:** Configure S3 bucket `yagye-kyb-documents` in the dev Docker
  environment. See `docs/data-engineering/floci-setup.md`.

**Complexity** — High. S3 integration, virus scanning, presigned URL flow.

---

### 3.2 `portal_screening_hits` — AML Screening Queue

**What it is**
A compliance queue of AML/sanctions screening hits for merchants, beneficial
owners, directors, and customers. Each hit records the list type (OFAC, EU
sanctions, PEP, adverse media), the matched name, match score, and disposition
status. Turbo Stream broadcasts on new hits so the compliance desk sees
incoming alerts in real time.

**Why it matters**
Onboarding a sanctioned entity is a regulatory catastrophe. The screening hit
queue is the human review layer on top of automated AML screening — a hit
stays open until a compliance analyst dispositions it as a false positive or
a confirmed match. A confirmed match blocks merchant activation absolutely
(DB CHECK on disposition → core command).

**PSP relevance**
Bank of Ghana licensing and correspondent banking relationships require
demonstrable AML controls. Without a screening queue, a PSP is flying blind.
The `match_score` column allows analysts to triage high-confidence hits first.

**Phase** — P21b

**Prerequisites** — AML screening provider integration in Core (Comply
Advantage, ComplyLaunch, or similar). Core emits `screening.hit.created`
events. SoD model guards on Core side for hit disposition commands.

**Implementation approach**

- **Core (Elixir):** `Compliance.ScreeningHits` context. Call the AML provider
  after KYB document collection. Parse results into `screening_hits` rows.
  Emit `screening.hit.created` outbox event.
- **Portal (Rails):** Migration. Karafka consumer. UI: compliance queue page
  (internal_staff only), with filters for status and list type. Disposition
  actions (`mark_false_positive`, `confirm_match`) POST to `/internal/
  screening-hits/:id/disposition`.
- **Simulator:** A fixture-based AML stub for dev/CI (specific MSISDNs or
  names trigger a hit response).

**Complexity** — High. Involves a third-party integration, SoD controls, and
compliance workflow UI.

---

## 4. Ops Tooling

---

### 4.1 `impersonation_sessions` — Staff Support Impersonation

**What it is**
A time-boxed, read-only, audited mechanism for internal staff to view the
portal as a specific merchant user. Every impersonation session requires a
mandatory reason (support ticket reference), is capped at 60 minutes, and
shows a visible banner to anyone who opens the browser. A DB CHECK constraint
ensures no code path can ever create a write-enabled impersonation session.

**Why it matters**
Without impersonation, support tickets that require seeing exactly what a
merchant sees take longer to resolve — the ops analyst must recreate the
merchant's state from database records. With it, the analyst can reproduce the
issue in one click.

**PSP relevance**
Financial support escalations are time-sensitive. A payment the merchant claims
is missing, a balance that does not match expectations — these need fast
diagnosis. Impersonation reduces mean-time-to-resolution.

**Phase** — Ops tooling (P14 area)

**Prerequisites** — Internal staff roles exist. Pundit policies exist.
`user_sessions` should be built first (session revocation on impersonation
end).

**Implementation approach**

- **Portal (Rails):** Migration with `CHECK (read_only = true)`. Create
  `ImpersonationSession` model. Ops analyst clicks "Impersonate" on the
  merchant detail page. The controller opens a session with the merchant user's
  permissions but under the staff user's audit trail. A sticky banner renders
  on every page during impersonation. The session auto-expires at `expires_at`
  and can be ended manually.
- **Audit log:** Every page view during an impersonation session is logged with
  the `impersonation_session_id` so the audit trail shows exactly what was
  accessed.

**Complexity** — Medium. The session mechanism is the complex part; the UI is
straightforward.

---

### 4.2 `portal_breaks` + `break_notes` — Reconciliation Break Queue

**What it is**
`portal_breaks` is the ops analyst's primary work queue: a denormalised read
model of reconciliation breaks detected by Core. A break is a discrepancy
between Yagye's ledger and a provider's settlement file. `break_notes` is an
append-only investigation thread attached to each break — analysts record their
findings, escalations, and resolution rationale.

**Why it matters**
Reconciliation breaks are a core ops responsibility for any PSP. A break left
unresolved is either a loss (Yagye is owed money it has not collected) or a
liability (Yagye has paid out more than it received). The severity and SLA
columns enforce that breaks are triaged and resolved within agreed timescales.

**PSP relevance**
Settlement reconciliation accuracy is audited by the Bank of Ghana. Yagye
must demonstrate that every break is detected, investigated, and resolved. The
`portal_breaks` queue is the evidence trail for that audit. Turbo Stream
broadcasts on new breaks so the analyst desk sees them as they arrive.

**Phase** — Requires reconciliation runs in Core to be live first.

**Prerequisites** — Core `reconciliation_runs` context must produce
`reconciliation.break.detected` outbox events. The Core recon trigger (P13
Step 0 gap) must be in place.

**Implementation approach**

- **Core (Elixir):** `Reconciliation` context produces break records. Emits
  `reconciliation.break.detected`, `reconciliation.break.resolved` events.
- **Portal (Rails):** Migrations for both tables. Karafka consumer projecting
  break events. UI: a "Breaks" queue page (ops only), sortable by severity and
  SLA due date. A break detail drawer with the note thread. The `visibility`
  column on `break_notes` gates which notes a merchant can see if a
  merchant-visible resolution note is needed.

**Complexity** — High. Depends on a Core domain (reconciliation) that is
itself complex.

---

## 5. Platform Analytics (Ops-Facing)

These three tables are the Yagye ops team's internal finance dashboard. They
are not visible to merchants.

---

### 5.1 `portal_platform_daily_metrics` — Platform P&L

**What it is**
A daily snapshot of platform-wide transaction volume, Yagye's gross revenue
from fees, provider costs, and gross margin. Also tracks refund and dispute
volume. Powers the ops finance dashboard.

**Why it matters**
Yagye's leadership needs a daily P&L view. Without it, understanding revenue
vs cost requires ad-hoc SQL queries against the ledger — not sustainable as
volume grows. The `psp_margin_revenue` vs `orchestration_revenue` split allows
tracking Model A vs Model B revenue separately as the business scales.

**Phase** — P17+

**Prerequisites** — `fee_records` populated with `party` correctly set
(`platform | provider`). Settlement batch pipeline producing net amounts.
A DuckDB ETL job or Oban cron that recomputes daily metrics.

**Implementation approach**

- Recompute nightly from `fee_records` grouped by `(day, currency, mode)`.
- `platform_revenue` = SUM fee_records WHERE party = 'platform'
- `provider_cost` = SUM fee_records WHERE party = 'provider'
- `gross_margin` = platform_revenue - provider_cost
- Upsert the results into `portal_platform_daily_metrics`.
- UI: accessible only to `ops_manager` / `ops_analyst` roles.

**Complexity** — Medium.

---

### 5.2 `portal_platform_fee_invoices` — Platform Fee Invoice Tracker

**What it is**
A read model of fee invoices Yagye issues to enterprise merchants (Model B).
Tracks the invoice lifecycle from draft through collection, and the collection
method (`cross_net | monthly_invoice | direct_debit`).

**Why it matters**
Enterprise merchants pay Yagye orchestration fees. These fees are invoiced on a
schedule and collected via one of three methods. Without a tracker, collections
require manual reconciliation between the invoicing system and bank statements.

**Phase** — P16+ (enterprise merchants, Model B)

**Prerequisites** — `platform_fee_invoices` table in Core and the fee invoicing
domain logic. Core emits `platform_fee_invoice.*` events.

**Complexity** — Medium.

---

### 5.3 `portal_platform_provider_costs` — Provider Cost Intelligence

**What it is**
A daily table of per-provider transaction costs: transaction count, gross
volume, total provider fees paid, and effective fee rate in basis points.
The `average_fee_bps` column flags contract violations: if a provider's
effective rate drifts above the contracted rate, something is wrong.

**Why it matters**
Provider cost is Yagye's largest COGS item. A 10bp drift in a provider's
effective fee rate on high volume is material. This table turns a financial
control that would otherwise require periodic manual analysis into a continuous
automated alert.

**Phase** — P17+

**Prerequisites** — `fee_records` populated with `party = 'provider'` and
`provider_code` correctly set.

**Complexity** — Low (once fee_records is reliable).

---

## 6. Core Features Deferred

These are features in `yagye_core` (Elixir) that are documented in the
DBML or ADRs but not yet implemented.

---

### 6.1 `data_subject_requests` — GDPR/NDPA Data Subject Rights

**What it is**
A workflow for handling data subject requests (DSARs): access, rectification,
erasure, portability, and objection rights under GDPR and Ghana's Data
Protection Act. The `controller` column correctly routes requests: Yagye
answers its own data; merchants answer for their customer data.

**Why it matters**
Receiving a DSAR and failing to respond within the statutory window (30 days
under GDPR, 21 days under Ghana DPA) is a regulatory violation. The table
exists to make DSAR handling a structured, auditable workflow rather than an
ad-hoc email chain.

**Phase** — P22+

**Prerequisites** — Real AWS for crypto-shred of KMS-encrypted PII blobs.
`retention_policies` must exist first so the erasure path knows what to delete
vs what must be retained.

**Complexity** — High. Involves PII handling, legal review, and irreversible
data operations.

---

### 6.2 `retention_policies` — Data Lifecycle Automation

**What it is**
A table-backed data retention policy registry. Each row defines a data class
(PII, FIN, SEC, EVD), its retention period, the legal basis for keeping it,
and the deletion method (`hard_delete | crypto_shred | anonymise | never`).
A `RetentionSweep` job runs nightly to enforce policies.

**Why it matters**
Keeping data longer than legally required is a liability. Deleting data too
soon violates financial record-keeping obligations (Ghana's Payment Systems and
Services Act requires 7 years for transaction records). A policy registry makes
these decisions explicit, auditable, and automated rather than implicit and
manual.

**Phase** — P22+

**Complexity** — Medium.

---

### 6.3 Customer-Scoped Delegation Tokens (ADR-0024)

**What it is**
A `customer_tokens` table scoped to `(merchant_id, customer_id)`. A merchant
issues a short-lived token for a specific customer session. The token permits a
restricted set of operations (pay, check balance, list transactions) and is
bounded by the merchant's velocity limits.

**Why it matters**
AI agents (agentic API clients) authenticating on behalf of end-users need
a token that is scoped to that user's account, not the merchant's full API key.
Without this, an agent with a merchant API key can access any customer's data.

**Phase** — P13 extension (small scope per ADR-0024)

**Complexity** — Medium.

---

### 6.4 Customer Wallets — Ledger Account Extension (ADR-0024)

**What it is**
A `customer_wallet` ledger account type anchored to `(merchant_id,
customer_reference)`. Enables neobank-style stored-value use cases where an
agent manages a persistent balance for a WhatsApp user.

**Phase** — P16+

**Prerequisites** — Customer delegation tokens (6.3) must exist first.

**Complexity** — High. Requires a ledger migration and new posting rules.

---

### 6.6 `screening_providers` + `screening_subjects` + `screening_requests` — Full AML/PEP Infrastructure (P21b)

**What it is**
Three tables that implement the production AML/PEP screening pipeline in Core:

- **`screening_providers`** — A registry of AML data providers (ComplyAdvantage, World-Check,
  LexisNexis). Each row names the Elixir adapter module, the lists supported (OFAC, EU, UN, UK
  HMT, BoG Watch List, PEP, adverse media), and the default lists queried per request. The
  `ScreeningAdapter` behaviour is already defined; only the adapter module changes when
  switching providers.

- **`screening_subjects`** — One row per screened entity: the merchant itself, each
  beneficial owner, each director, and optionally high-value customers. Owns the screening
  schedule: `last_screened_at`, `next_screening_at`, and `screening_frequency_days` (365 for
  clean subjects, 180 for PEPs/RCAs, 30 for high-risk or confirmed PEPs). A partial index on
  `next_screening_at WHERE screening_status NOT IN (confirmed_match_blocked, suspended)` drives
  the `ScreeningSchedulerWorker` without full-table scans.

- **`screening_requests`** — An immutable audit record of every API call to a screening
  provider. A failed or timed-out request is retried by creating a NEW row — the failed row is
  kept as evidence. Stores the provider's own search reference (`search_ref`) and the full raw
  response (`raw_response` jsonb, `[EVD]`). Regulators will ask for this verbatim.

**Why these three tables — not just `screening_hits`?**
`screening_hits` (already migrated, P11) captures the per-match results. These three tables
capture the scaffolding around it:
- Without `screening_providers`, the adapter module is hardcoded — no runtime provider
  switching or multi-provider comparison.
- Without `screening_subjects`, there is no ongoing rescreening schedule. FATF and BoG
  regulations require periodic monitoring, not just onboarding screening.
- Without `screening_requests`, there is no immutable audit trail per API call — only the
  hits are stored, not the fact that the check was run and what the full response was.

**PSP relevance**
Bank of Ghana licensing and correspondent banking onboarding (the prerequisite for bank
settlement) both require demonstrable AML controls. "We screen on onboarding" is not enough —
examiners ask: "which lists, via which provider, on which date, for which person, and what did
the raw response say?" Only `screening_requests` answers that. PEP monitoring frequency must
be documented — only `screening_subjects` holds that schedule.

**Phase** — P21b

**Prerequisites** — `screening_hits` is already migrated. The `ScreeningAdapter` behaviour
exists (`YagyeCore.Compliance.AmlProvider` with `StubScreeningAdapter` and `ComplyAdvantage`
adapters). The three new tables must be migrated together at P21b Step 0 before any real AML
provider calls are made.

**Implementation approach**

- **Core (Elixir):** Three migrations in one step. Seed `screening_providers` with the
  `stub` provider for dev/test and `comply_advantage` for prod. Build
  `ScreeningSchedulerWorker` (Oban cron, daily) to find subjects where
  `next_screening_at <= now()` and enqueue `ScreeningWorker` per subject.
  `ScreeningWorker` creates the `screening_request` row, calls the adapter, creates
  `screening_hits`, updates `screening_subject.last_screened_at` and sets
  `next_screening_at` based on `screening_frequency_days`.
- **On onboarding:** when a merchant is approved or a beneficial owner is added, enroll
  the subject in `screening_subjects` with `next_screening_at = now()` so the scheduler
  picks them up within the hour.
- **SoD:** `screening_hits.raised_by` and `dispositioned_by` already have the CHECK
  constraint (`20261006120000`). No additional SoD is needed at this layer.
- **Compliance event:** emit `compliance.screening_hit_raised` via the outbox when
  `hit_count > 0` after a completed request. The portal's `ScreeningHitsConsumer`
  (§3.2) listens for this.

**Complexity** — High. Provider adapter interface, scheduler, background job chain, outbox
event, and the enrollment hook across three separate contexts (Merchants, Compliance,
BeneficialOwners).

---

### 6.5 Stablecoin Provider Adapter (ADR-0024)

**What it is**
A standard `ProviderAdapter` implementation for a stablecoin rail (USDC/USDT
via Yellow Card, Bridge, or BVNK). Modelled as just another provider — the
ledger gets a `stablecoin_float` account type.

**Phase** — Post-P22 (requires banking relationship and regulatory sign-off)

**Prerequisites** — Real AWS, crypto rail regulatory approval.

**Complexity** — High.
