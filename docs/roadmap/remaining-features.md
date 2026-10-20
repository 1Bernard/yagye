# Remaining Features — Build Catalog

**Last updated:** 2026-10-18

Every feature that is documented in the DBML but not yet migrated or built.
For each feature: what it is, why it matters in a PSP context, the phase it
belongs to, what must exist first, and how to implement it.

The `// DEFERRED:` comment in `docs/schema/yagye-portal.dbml` or
`docs/schema/yagye-core.dbml` is the single canonical phase tag per table.
This document adds the engineering context that the DBML cannot carry.

---

## 1. Ready Now (Unblocked)

These features have no external dependencies. Everything they need — auth,
roles, consumers, the projection pipeline — is already running in P13/P13.5.
They should be the next things built.

---

### 1.1 `user_sessions` — Persistent Session Tracking

**What it is**
A durable, per-device session record that replaces ephemeral Devise cookies
as the session anchor. Each login creates a `user_sessions` row keyed to a
hashed session token. Sessions can be listed, inspected, and individually
revoked by the user or by ops.

**Why it matters**
Devise's default cookie session gives Yagye no visibility into where a user
is logged in. If an account is compromised, there is no way to invalidate
all active sessions without changing the user's password. For a PSP where
users can see settlement data, manage API keys, and approve KYB applications,
that is an unacceptable gap.

Refresh rotation with reuse detection is a critical security property: when a
stolen refresh token is presented, the system detects that an already-used
token is being replayed and revokes the entire session family, logging the
incident.

**PSP relevance**
Compliance frameworks for payment institutions (PCI-DSS, Bank of Ghana
licensing) require demonstrable session management controls. A `user_sessions`
table gives auditors a queryable log of every active session, the device it
belongs to, and when MFA was last satisfied.

**Phase** — P13 extension (unblocked now)

**Prerequisites** — None. Devise auth is complete. The `users` table exists.

**Implementation approach**

- **Portal (Rails):** Add the migration for `user_sessions` (schema is defined
  in the DBML). Override Devise's `sign_in` and `sign_out` to write/revoke the
  session row. Store the session token digest in the cookie instead of the raw
  token. Add a "Security" page under Settings that lists active sessions and
  offers individual revocation.
- **Core involvement:** None. This is entirely a portal feature.
- **Simulation:** None needed.
- **Events:** No new domain events. If you want to broadcast "new login from
  unknown device", emit a portal notification row (using the existing
  `portal_notifications` table) from the session creation callback.

**Schema** (from DBML)
```
user_sessions
  id bigserial pk
  user_id bigint → users.id
  session_token_digest text unique  -- [SEC] hashed, never plaintext
  device_fingerprint text           -- new device triggers email alert
  ip text
  user_agent_hash text              -- [PII] hashed
  mfa_satisfied_at timestamptz
  expires_at timestamptz            -- 12h internal_staff, 30d merchant_user
  revoked_at timestamptz
  created_at timestamptz
```

**Complexity** — Medium. The session management override in Devise is
non-trivial and must be tested carefully. The security page itself is Low.

---

### 1.2 `saved_filters` — Persisted Table Filters

**What it is**
A way for portal users to save and name a set of filter criteria applied to a
list view (payments, settlements, reconciliation). A saved filter can optionally
be shared across all users of the same merchant account.

**Why it matters**
Ops analysts spend much of their day in the same filtered views: "show me all
disputed payments from MTN in the last 7 days". Saving those filters eliminates
the overhead of rebuilding them on every login. For merchant finance teams,
shared saved filters create a consistent view across the team.

**PSP relevance**
Operational efficiency compounds over time. A reconciliation analyst who can
open their saved "unmatched settlements for the current period" in one click
processes breaks faster. Time-to-resolution on financial exceptions is a direct
quality-of-service metric for a PSP.

**Phase** — P13 extension (unblocked now)

**Prerequisites** — None.

**Implementation approach**

- **Portal (Rails):** Add the migration. Create a `SavedFilter` model with a
  `filters jsonb` column. The controller stores the current query parameters as
  JSON when the user clicks "Save". On load, deserialise the JSON and apply it
  to the query object. The `namespace` column scopes filters to the correct
  list view (`Payments::`, `Settlements::`, etc.).
- **Core involvement:** None.
- **UI:** A dropdown on each list page: "Saved filters → [names] → Save
  current". Small, composable — does not require a dedicated page.

**Schema**
```
saved_filters
  id bigserial pk
  user_id bigint → users.id
  namespace text          -- 'Payments::' | 'Settlements::' | etc.
  name text
  filters jsonb
  shared_with_merchant boolean
  created_at / updated_at timestamptz
```

**Complexity** — Low.

---

### 1.3 `processed_events` — Consumer-Side Deduplication Log

**What it is**
A durable deduplication table for Karafka consumers. When a consumer processes
an event (e.g. `payment.succeeded` to update `portal_merchant_balances`), it
inserts a row into `processed_events` first. If the insert succeeds (no
conflict), it continues processing. If it gets a unique violation, the event
was already processed and the consumer skips it.

**Why it matters**
Redpanda (Kafka-compatible) guarantees at-least-once delivery. When a consumer
crashes mid-batch and restarts, it re-reads from the last committed offset and
re-delivers events it already processed. For counter-style projections like
merchant balances, replaying a `payment.succeeded` event without dedup would
add the payment amount twice — a material misstatement.

See `docs/architecture/engineering-concepts.md §Exactly-once processing` for
the full explanation of why version fencing alone cannot protect counters.

**PSP relevance**
A PSP showing a merchant their balance that is off by even one transaction
destroys trust. The `processed_events` table is the mechanism that ensures
balance projections are accurate regardless of consumer restarts, rebalances,
or Redpanda redeliveries.

**Phase** — P13 extension (unblocked now; in-memory dedup is the current
interim)

**Prerequisites** — The Karafka consumer infrastructure exists. Redpanda is
running (at P14, the current setup uses Oban relay).

**Implementation approach**

- **Portal (Rails):** Add the migration. The `processed_events` table has a
  composite primary key `(event_id, consumer)`. In each consumer that operates
  on a counter (currently `MerchantBalanceConsumer`), wrap the processing in:
  ```ruby
  result = ProcessedEvent.insert(
    {event_id: envelope.event_id, consumer: self.class.name, processed_at: Time.current},
    on_duplicate: :skip, returning: false
  )
  return if result.count == 0  # already processed
  # proceed with counter update
  ```
- A daily sweep job deletes rows older than 30 days (the DBML note). A
  Redpanda consumer will never replay an event older than the retention window.
- **Core involvement:** None. This table is portal-side only.

**Schema**
```
processed_events
  event_id text  pk (composite)
  consumer text  pk (composite)
  processed_at timestamptz
```

**Complexity** — Low. Three lines of code per consumer, one migration.

---

### 1.4 `portal_merchant_balances` — Merchant Balance Read Model

**What it is**
A pre-computed table of each merchant's available, pending, reserved, and
in-transit balances, updated by the outbox projection pipeline. Replaces the
current pattern of querying `proj_merchant_balances` in Core.

**Why it matters**
The merchant balance is the most-viewed figure on the portal dashboard. It
appears on every page load for the merchant. Fetching it from Core on every
request adds a cross-service HTTP call to every page render. A portal-side
projection eliminates that latency and eliminates Core as a dependency for
every dashboard load.

**PSP relevance**
Merchants make operational decisions based on their balance (timing of payouts,
reserve acknowledgment, dispute funding). A stale or missing balance is a
support escalation waiting to happen. The `last_applied_at` column surfaces
projection lag so the UI can show "updated N seconds ago" rather than a stale
number with no warning.

**Phase** — P13 extension (unblocked now)

**Prerequisites** — Outbox events `payment.succeeded` and `payout.completed`
are already being emitted. A Karafka consumer exists for payment events.
`processed_events` should be built first (1.3) to protect the counter.

**Implementation approach**

- **Portal (Rails):** Add the migration. Create a `PortalMerchantBalance` model.
  Update the existing `PaymentConsumer` (or a new `BalanceConsumer`) to upsert
  into `portal_merchant_balances` on `payment.succeeded`: increment `available`,
  decrement `pending`. Gate the update on `processed_events` insert success.
- The balance is per `(merchant_code, currency, mode)` — the composite PK
  ensures simulation and live balances are always separate.
- **Core involvement:** No new Core changes. The events are already emitted.

**Schema**
```
portal_merchant_balances
  merchant_code text  pk (composite)
  currency char(3)    pk (composite)
  mode text           pk (composite)
  available bigint
  pending bigint
  reserved bigint
  in_transit bigint
  last_event_id text
  last_applied_at timestamptz
```

**Complexity** — Medium. The consumer update logic is straightforward but must
be protected by `processed_events` and handle currency/mode scoping correctly.

---

### 1.5 `portal_daily_metrics` — Per-Merchant Daily Volume

**What it is**
A pre-computed daily metrics table per merchant, currency, and mode: payment
count, success/failure counts, gross volume, refund volume, and chargeback
count. Powers the volume chart on the merchant overview page.

**Why it matters**
Merchants and ops analysts review volume trends daily. Computing this live
from the `portal_payments` table on every chart load requires a full-table
aggregate that becomes expensive as transaction volume grows. Pre-computing it
nightly makes the chart render in a single index read.

**PSP relevance**
Volume visibility is a basic merchant expectation. A chart that loads in 50ms
vs one that times out is the difference between a self-service merchant and one
who calls support. For a PSP serving merchants at scale, dashboard performance
directly affects support ticket volume.

**Phase** — P13 extension (unblocked now)

**Prerequisites** — `portal_payments` table is populated. A background job
scheduler is running (Solid Queue is already configured).

**Implementation approach**

- **Portal (Rails):** Add the migration. Create a `DailyMetricsRecomputeJob`
  that runs hourly via Solid Queue. The job does a single aggregation query
  over `portal_payments` grouped by `(merchant_code, day, currency, mode)` and
  upserts the results. Recompute-from-source is safe (idempotent), unlike
  incremental counters.
- **Core involvement:** None.
- The DBML note explains the choice: "A wrong count self-corrects; a wrong
  amount is a misstatement — hence recompute, not increment."

**Complexity** — Low.

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

### 6.5 Stablecoin Provider Adapter (ADR-0024)

**What it is**
A standard `ProviderAdapter` implementation for a stablecoin rail (USDC/USDT
via Yellow Card, Bridge, or BVNK). Modelled as just another provider — the
ledger gets a `stablecoin_float` account type.

**Phase** — Post-P22 (requires banking relationship and regulatory sign-off)

**Prerequisites** — Real AWS, crypto rail regulatory approval.

**Complexity** — High.
