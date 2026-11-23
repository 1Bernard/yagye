# Data Model Design — Yagye

This document explains why the databases are shaped the way they are. It is written
in the tradition of *Designing Data-Intensive Applications* — not a schema reference,
but an account of the design decisions, the forces that drove them, the trade-offs that
were accepted, and the things that remain incomplete.

Three databases. Three separate concerns.

```
yagye_core      — the financial record. Single writer. Elixir owns it.
yagye_portal    — human identity, human workflow, portal read models. Rails owns it.
gateway_simulator — a model of the external contract. Deliberately alien vocabulary.
```

---

## 1. Data Types: The Foundational Choices

### Money is BIGINT, never NUMERIC or FLOAT

Every amount in the schema is `BIGINT` in minor units (pesewas, cents) with an adjacent
`CHAR(3)` currency code. This was the first decision and it constrains everything else.

**Why not NUMERIC(12,2)?** `NUMERIC` is correct for money in accounting terms, but it
introduces a decimal point that every piece of code must manage consistently. If two
systems disagree about where the decimal is — one sends `{"amount": 100}` meaning GHS 100,
another meaning GHS 1.00 — the error is silent and financial. With integers, `100` is
always 100 pesewas everywhere. The conversion to display units happens exactly once, in
the presentation layer.

**Why not FLOAT?** `0.1 + 0.2 ≠ 0.3` in IEEE 754. A single float rounding error in a
settlement calculation is a reconciliation break that takes a day to find.

**The currency must be adjacent.** `amount BIGINT` without `currency CHAR(3)` on the same
row is meaningless. Joining to a parent table to find the currency introduces a query and
a potential for the join to return the wrong currency if data is denormalised differently
at different levels. Every money-bearing table in yagye_core carries both.

### UUIDs: version matters

Internal PKs are UUID (UUIDv7 — application-generated, time-ordered). Public IDs are
prefixed ULIDs: `pay_01J...`, `mch_01J...`, `stl_01J...`.

**Why not sequential integers?** An integer PK on `payments` tells a competitor exactly
how many payments you processed between two API calls. ULID prefixes (`pay_`, `mch_`) tell
an API consumer what kind of object they have without an extra field. A client that receives
`pay_01J...` and passes it to `/settlements/:id` gets a 404 with a useful error rather than
a type confusion bug.

**The exception: `ledger_postings.id` is `BIGSERIAL`.** The note says why: "dense, ordered,
never exposed, and `last_posting_id` is a meaningful watermark." The balance cache
(`ledger_balances.last_posting_id`) must point to the highest posting that has been
accounted for. A UUID cannot serve as a watermark — you cannot say "give me all postings
after this UUID" without a secondary ordering column. The bigserial is the cursor.

**Another exception: `outbox_messages.id` is `BIGSERIAL`.** The relay reads in `id` order.
A UUID here would require an indexed `inserted_at` secondary sort, which is not unique
under sub-millisecond burst writes. The bigserial is the queue position.

### Timestamps: Bitemporality

Every table with time-sensitive data carries two timestamps:

- `occurred_at` — when the event happened in the domain (what the customer and merchant care about)
- `recorded_at` — when the system recorded it (what an audit cares about)

This is bitemporality. The gap between them matters: a webhook that arrives 90 seconds late
records `occurred_at = webhook_timestamp` and `recorded_at = now()`. Without both, you cannot
answer "what did we know, and when did we know it?" — the question every regulatory examination
starts with.

`payment_events` has both. `ledger_entries` has `effective_at` (domain) and `recorded_at`
(system). `outbox_messages` has `occurred_at` (the payment event time, not the outbox write).

---

## 2. Concurrency and Correctness

### Optimistic Locking: `payments.version`

The `payments` table has a `version INTEGER` column, described as "optimistic lock AND event
ordering fence." This is the core concurrency control for the payment state machine.

**How it works:** Every state transition reads the current `version`, does its business logic,
and writes `UPDATE payments SET state = $new, version = version + 1 WHERE id = $id AND version = $expected`.
If another process updated the row between the read and the write, the update matches zero rows.
The application retries or raises a conflict error.

**Why optimistic, not pessimistic?** A payment processing 50 concurrent state transitions per
second with pessimistic locks (SELECT FOR UPDATE) would serialize every transition through
Postgres's lock manager. Optimistic locking assumes conflicts are rare — which they are for
payments, because each payment is an independent object — and pays no cost on the happy path.

**Where optimistic locking is conspicuously absent:** `settlement_batches`, `ledger_balances`,
`proj_merchant_balances`. These tables are mutated by background workers that may run
concurrently. They rely on different mechanisms:

- `ledger_balances` uses `last_posting_id` as a watermark — the update is `WHERE account_id = $id
  AND last_posting_id < $new_posting_id`, which is naturally idempotent and conflict-safe.
- `settlement_batches` relies on a unique index `(merchant_id, provider_id, currency, mode,
  period_start, period_end)` as the idempotency guard — the creation is atomic, not the
  update.
- `proj_merchant_balances` uses `last_event_id` deduplication to prevent double-counting,
  not version-based conflict detection.

### Pessimistic Locking: SELECT FOR UPDATE

The schema cannot express this, but several operations require it:

**Settlement sweep**: The worker that sweeps `succeeded` payments into a batch must lock the
payments it is claiming: `SELECT ... FOR UPDATE SKIP LOCKED`. Without `SKIP LOCKED`, two
concurrent workers would block each other. With `SKIP LOCKED`, the second worker skips rows
already locked by the first and processes a different set. This is PostgreSQL's queue pattern.

**Refund guard**: Before inserting a refund, the code locks the payment row to check
`SUM(refunds.amount) + new_amount <= payments.amount`. Without a lock, two concurrent
refund requests could both pass the check and together exceed the payment amount.

**Float balance updates**: `momo_float_balances` is updated on every payout. These need
`SELECT FOR UPDATE` to prevent two concurrent workers from both reading `balance = 10000`,
both passing the `>= payout_amount` check, and together overdrawing the float account.

### Idempotency: The `idempotency_keys` Table

This table is the most carefully designed in the schema. The note says: "The claim is inserted
BEFORE execution. A uniqueness constraint that fires after the side effect is not idempotency."

**The design:** On receipt of an idempotent request, the system tries to INSERT a row with
`state = in_progress`. If the INSERT fails (duplicate key), it reads back the existing row.
If `state = completed`, it returns the cached `response_body`. If `state = in_progress`, the
original request is still running — return 202 or wait.

**The lease:** `lease_expires_at` solves the crash recovery problem. If the process crashes
after inserting the idempotency row but before completing the work, the row stays `in_progress`
forever — blocking all retries. The lease gives it an expiry: after `lease_expires_at`, a new
attempt can re-claim the key and redo the work. Exactly-once becomes at-least-once-with-deduplication,
which is achievable. Exactly-once-without-leases is not.

**`request_fingerprint`**: Two requests with the same idempotency key but different bodies
(a conflicting retry) get a 422 — "you gave me the same key but asked for something different."
The fingerprint is a SHA-256 of the canonical request body, computed once at the API layer.

---

## 3. The Ledger: Financial Data Integrity

The double-entry ledger is the most rigorous part of the design.

### Why Double-Entry?

A single balance column on `merchants` is not enough for a PSP. The questions you need
to answer include:

- How much has this merchant earned this week? (`merchant_payable` account balance)
- How much is currently in settlement? (`settlement_approved` account balance)
- How much is withheld as reserve? (reserve account balance)
- Does the platform balance across all accounts? (sum of all debits = sum of all credits)

A double-entry ledger answers all of these without requiring any application-layer logic
to maintain the invariant. The invariant `SUM(debits) = SUM(credits)` is enforced at the
transaction level by a DEFERRED constraint trigger — not per-row, but per-commit.

### Immutability: Revoke UPDATE and DELETE

`ledger_entries` and `ledger_postings` are append-only. The schema note says:
"REVOKE UPDATE, DELETE from the app role." This is a Postgres-level control, not just
an application convention. The application role used by yagye_core cannot physically
issue UPDATE or DELETE on these tables. Corrections are made by inserting a reversing
entry — a new pair of postings that undo the original, with `reverses_entry_id` pointing
back. The audit trail includes both the error and the correction.

**Why is this important?** A financial record that can be silently edited is not a financial
record. If a regulator asks "show me every ledger movement," the answer must include the
correction and the reason for it, not a row that was quietly updated.

### `ledger_balances`: The Provable Cache

`ledger_balances` stores the running balance per account, updated incrementally. The note
says: "A cache with a PROVABLE relationship to truth: balance = SUM(signed postings WHERE
id <= last_posting_id). Verified nightly; disagreement is a P1."

This is the snapshot pattern for event sourcing. Rather than replaying all ledger postings
from the beginning to compute a balance (expensive), the system maintains a running sum and
periodically proves it matches reality. The `last_posting_id` is the replay cursor: if the
balance is ever suspect, replay postings from `last_posting_id` forward to verify.

---

## 4. The Outbox Pattern

`outbox_messages` is written in the **same transaction** as the state change that triggers it.
The note says: "This is what makes dual-write impossible."

**The problem without it:** If a payment succeeds and the application then tries to publish
an event to Redpanda, the two operations are separate. If the app crashes between them, the
payment is marked succeeded but no event was published. Downstream projections (portal read
models, the data lake) never learn about it. The portal shows a stale state indefinitely.

**With the outbox:** The event is in the database, written atomically with the state change.
A separate relay process reads `outbox_messages WHERE published_at IS NULL`, publishes to
Redpanda, and sets `published_at`. If the relay crashes, the message is still in the database.
The relay retries. Redpanda consumers deduplicate on `event_id`. The system is eventually
consistent, not silently inconsistent.

**The relay uses `id` order**, not `inserted_at` order. `inserted_at` is not unique under
concurrent inserts. The bigserial `id` is a strict total order. The relay reads
`WHERE published_at IS NULL ORDER BY id LIMIT 100` — a simple, cheap, correct queue scan.

---

## 5. Event Sourcing Lite: `payment_events`

The schema uses a subset of event sourcing — not the full commitment of rebuilding state
from events, but enough to get the audit trail and the event-driven integration.

`payment_events` has:
- `version` — ordered event sequence, matches `payments.version`
- `from_state` / `to_state` — state machine transition evidence
- `actor` — who triggered it (api key, user, system, webhook)
- `correlation_id` — survives long after the OTel trace expires
- `causation_id` — the event that caused this one (for chained operations)
- `occurred_at` vs `recorded_at` — bitemporality

**What this enables:**
1. Full audit trail: "who changed this payment and when"
2. Replay: build a projection by scanning `payment_events WHERE payment_id = $id ORDER BY version`
3. Debugging: `causation_id` chains let you trace "which webhook triggered which state change"

**What it does NOT do (deliberately):**
The system does NOT rebuild `payments` from `payment_events`. The `payments` table is the
authoritative state — not a projection. This is "event sourcing lite": events for audit,
state table for reads. Full event sourcing (rebuilding state from events) would require
all aggregates to be re-hydrated on every read — appropriate for some domains, expensive
for high-volume payment processing.

---

## 6. The Portal: CQRS Across a Database Boundary

The portal database contains NO money. No ledger, no payment state machine, no fee records.
The header says: "It contains NO money. Every financial mutation is a command to the core."

This is CQRS (Command Query Responsibility Segregation) across a service boundary.

**Commands** go from portal → core via HTTP API. "Approve this refund" is a POST to core,
not a direct UPDATE on `refunds`.

**Queries** are served from portal's own read models: `portal_payments`, `portal_settlements`,
`portal_breaks`, etc. These are written by Karafka consumers reading core's event stream.

**Why not just query core directly?**
1. The portal and core can scale independently. Under heavy payment load, adding portal
   read replicas doesn't help if every page load is a cross-service query.
2. The portal's read models are shaped for the portal's queries — denormalised, pre-joined,
   filtered. `portal_breaks` has `evidence jsonb` already assembled for the analyst. The
   analyst should not have to write SQL.
3. The portal holds NO credential for the core database. That absence is the control.

**The version fence:**
Every `portal_*` read model has `aggregate_version` and `last_event_id`. When a consumer
receives an event, it checks: `incoming_version > stored_aggregate_version`. If not, the
event is out of order or already applied — skip it. This prevents an older event from
overwriting a newer state.

**The counter exception:**
`proj_merchant_balances` and `portal_merchant_balances` carry a note: "MONEY counter —
deduped on event_id before incrementing. Version fencing does NOT make counters idempotent."

This is subtle. Version fencing says "apply this event only if the version is newer." But
for a running counter (total_volume, lifetime_payment_count), the check is different:
"did I already apply this specific event_id to this counter?" A later event at a higher
version does NOT tell you whether a specific previous event was counted. Hence: deduplicate
on `event_id`, not on `aggregate_version`, for counters.

---

## 7. Separation of Duties (SoD)

SoD appears in nine tables, all enforced at the database layer with `CHECK` constraints:

| Table | Constraint |
|---|---|
| `merchants` | `reviewed_by <> approved_by` |
| `merchant_applications` | `reviewed_by <> approved_by` |
| `service_agreements` | (signatory evidence, not SoD) |
| `screening_hits` | `dispositioned_by <> raised_by` |
| `pricing_plans` | `created_by <> activated_by` |
| `pricing_rules` | `created_by <> approved_by` |
| `refunds` | `approved_by <> initiated_by` |
| `payouts` | `approved_by <> requested_by` |
| `payout_destinations` | `verified_by <> added_by` |
| `settlement_batches` | `dispatch_approved_by` (implicit SoD via ops workflow) |
| `platform_fee_invoices` | `write_off_initiated_by <> write_off_approved_by` |
| `settlements` | `write_off_initiated_by <> write_off_approved_by` |
| `merchant_reserves` | `created_by <> approved_by` |
| `adjustment_approvals` | `approved_by <> proposed_by` |

**Why at the database level, not just the application?**
An application-layer check is bypassed by a migration, a direct database connection, or a
bug in the approvals controller. A `CHECK` constraint fires on every write, from every
writer, including future ones not yet written. The core schema note on `adjustment_approvals`
is explicit: "The SoD constraint only protects you if it lives in the database that the
single writer uses."

---

## 8. PII Isolation: Crypto-Shredding

`pii_vault` is the design for GDPR right-to-erasure under a constraint: financial records
must be retained for 7 years, and those records may reference customers.

**The conflict:** A customer wants to be erased. GDPR says erase. AML regulations say
"keep the transaction record." You cannot delete the payment. You cannot keep the PII.

**Crypto-shredding:** PII (email, name, MSISDN, DOB) is stored encrypted with a KMS key
unique to that subject (`kms_key_id` per `subject_ref`). To erase: destroy the KMS key.
The ciphertext remains in the database — provably unreadable, indistinguishable from random
bytes. The `pii_vault.erased_at` column records when erasure happened. The payment record
stays, with its `customer_subject_ref`, pointing to a ciphertext that cannot be decrypted.

**What stays outside the vault:** `customers.email_hash` (HMAC — match without revealing).
`payment_mobile_money_details.msisdn_hash` (same). The hashes allow deduplication and velocity
checks without decrypting PII. Destroying the KMS key invalidates the plaintext without
invalidating the hash's utility for future lookups.

---

## 9. Cardinality, Indexing, and What Was Planned

### High-Volume Tables

**`payment_events`** — one row per state transition per payment. At 10,000 payments/day
with 4 events each, that is 1.46 billion rows in a year. The schema notes `api_requests`
is "partitioned monthly, 90 days hot, then archived." The same strategy applies to
`payment_events` and `checkout_events` but is not yet explicit in the schema. This is
a gap: at current growth, `payment_events` needs `PARTITION BY RANGE (occurred_at)` with
a monthly or quarterly cadence.

**`outbox_messages`** — the relay reads `WHERE published_at IS NULL ORDER BY id`. After
publishing, `published_at` is set. Over time the table grows with published rows that are
never re-read. A nightly job should sweep rows where `published_at IS NOT NULL AND
inserted_at < now() - interval '7 days'`. This is not documented in the schema.

**`ledger_postings`** — bigserial PK, append-only, one row per debit or credit. At 2 postings
per payment event (each ledger_entry has debit + credit), 10,000 payments/day = 7.3 billion
rows in a year. This table needs partitioning by time before P22. The `last_posting_id`
watermark design already anticipates this — a range partition scan from `last_posting_id`
forward is efficient in partitioned tables.

### Index Analysis

**Good indexes:**
- `payments`: `(merchant_id, inserted_at)` — the keyset pagination index. Correct.
  `(state, updated_at)` partial for stuck payments — also correct.
- `screening_subjects`: `(next_screening_at)` partial `WHERE NOT IN (blocked, suspended)` —
  the scheduler only picks up active subjects. Correct partial index usage.
- `idempotency_keys`: `(merchant_id, key)` unique — the atomic claim point.
- `outbox_messages`: Missing. The relay needs a partial index:
  `CREATE INDEX ... ON outbox_messages (id) WHERE published_at IS NULL`. Without it, the relay
  scan touches all historical rows.

**Cardinality notes:**
- `api_keys`: low cardinality on `mode` (3 values), `kind` (2 values) — these should be
  in composite indexes, never standalone. `(merchant_id, mode, key_prefix)` is correct.
- `payment_events`: `(payment_id, version)` unique — correct. Version gaps are impossible
  because Ecto's optimistic lock increments and writes atomically.
- `checkout_events`: no unique index — these are analytics rows. Correct.

### The `customers.lifetime_volume_currency` Problem

A customer that pays GHS 500 twice is straightforward: `lifetime_gross_volume = 100000`,
`lifetime_volume_currency = GHS`. But a customer that pays GHS 500 and then USD 50 is not.
The current schema stores one currency. This means lifetime volume is in whichever currency
the first payment used, and all subsequent different-currency payments are added at face
value with no FX conversion — silent data corruption.

**Fix:** Either restrict a customer record to one currency (acceptable for now — Ghana is GHS),
or move to a `jsonb` map `{GHS: 100000, USD: 7000}`. Given current scope (Ghana, GHS),
the single-currency approach is acceptable but should be documented as a constraint, not a gap.

---

## 10. What Was Designed Well and Why

### The Three-State Settlement Flow

`expected_net` and `reported_net` are NEVER overwritten by each other. The variance is a
`GENERATED ALWAYS AS (reported_net - expected_net) STORED` column — it cannot go stale.
This is the reconciliation model in one design decision: build in expectations as first-class
data, compare them to actuals, surface the difference. Most payment systems store only what
happened. Yagye stores what should have happened, what did happen, and the gap between them.

### The Simulator Vocabulary Barrier

The gateway simulator uses CHARGE not PAYMENT, PENDING_AUTH not requires_action, WALLET not
mobile_money. This is deliberate. If any simulator vocabulary appears in yagye_core, CI fails.
This is an anti-corruption layer enforced by grep, not by team discipline. Team discipline
erodes. CI does not.

### The Checkout Session / Payment Separation

`checkout_sessions` and `payments` are separate tables with separate PKs. A checkout session
can exist without a payment (the customer abandoned). A payment only exists once a method
is confirmed. The session's `total_amount` is set at creation and NEVER accepted from the
browser — it comes from the merchant's server-side checkout session creation. The browser
only submits the method choice, not the amount. This eliminates the entire class of
price-tampering attacks.

### `payout_destinations.fingerprint` with Hold

When a payout destination's account details change, a new `fingerprint` is computed and
`hold_until = now() + 24h` is set. No payout can be dispatched during the hold. This
catches the most common account-takeover cash-out pattern: attacker changes the settlement
bank account, immediately triggers a payout. The 24-hour hold gives ops time to notice
the change.

---

## 11. What Is Missing or Incomplete

### No Partition Strategy Documented

`api_requests`, `payment_events`, `checkout_events`, `outbox_messages`, `ledger_postings` —
all will grow without bound. The schema notes "partitioned monthly" on `api_requests` but
does not express the partition. A formal migration plan for each high-volume table is needed
before P22 traffic arrives.

### No Explicit Snapshot Strategy for Event-Sourced Projections

The projections (`proj_merchant_balances`, `proj_payment_summaries`) are updated incrementally.
If a consumer falls behind by 10,000 events (crash, slow worker), replaying from the
`last_event_id` to current takes time. There is no snapshot: "as of event X, the balance
was Y; replay only from X onward." For the current scale this is acceptable. At 100k
events/day it is not.

### `outbox_messages` Has No Cleanup Job

Old published outbox messages accumulate. A sweep job on `WHERE published_at < now() - 7d`
is not documented. At 10,000 payments/day this table grows by 50,000+ rows/day (5 events
per payment average) and is never shrunk.

### Advisory Locks for Settlement Worker

The settlement batch creation uses a unique index as an idempotency guard. But if two workers
race to create the batch, both pass the existence check, both try to insert, one wins and the
other gets a unique constraint violation. The application handles this, but it is unpleasant.
A `pg_advisory_lock` on `(merchant_id, provider_id, period_start)` would make the exclusion
explicit and cheaper than a unique constraint violation round-trip.

### `customers.lifetime_volume_currency` Single-Currency Assumption

Documented above. Add a schema-level comment asserting this is a GHS-only constraint.

### No `payment_link_id` FK on `invoices`

`invoices.payment_link_id` references `payment_links.id` but the FK is noted as deferred
to P16. The row exists in DBML as a nullable column. Until the FK is added, nothing prevents
an invoice pointing to a non-existent payment link. The P16 Step 0 task is documented in
memory.

---

## 12. The OLAP Layer Design

### The Three-Database Principle Applied to OLAP

Just as the portal has no money and the core has no human identity, the OLAP layer has no
transactional semantics. It is not a faster version of the OLTP database — it is a different
shape for different questions.

**What OLAP is for in Yagye:**
- "Which provider had the highest error rate yesterday, by method and currency?"
- "What is the 90-day revenue trend, broken by merchant risk tier?"
- "Which merchants account for 80% of chargebacks?"

None of these queries should run against PostgreSQL. At 10M payments they cause table scans
that hold autovacuum back and slow down the payment API.

### The Bronze / Silver / Gold Medallion

**Bronze** — raw, append-only event envelopes from `outbox_messages`. One row per domain
event, as-is. Never corrected, never deleted. The schema: 9 event families, validated at
write time by JSON Schema, rejected envelopes routed to `events/rejected/` prefix rather than
silently dropped. Partitioned by `dt=YYYY-MM-DD`.

**Silver** — deduplicated, typed, one row per entity state at event time. The Silver transform
is the place where:
1. Duplicates are removed (`DISTINCT ON (event_id)`, keeping earliest)
2. Payload is flattened (`envelope->>'amount'` becomes an INTEGER column)
3. Event-grain is collapsed to entity-grain (many `payment.*` events → one payment row)

**Gold** — aggregated, star schema, pre-joined. Business questions answered directly.

### Grain Decisions for Each Gold Table

**`payment_facts`** — grain: one row per payment (not per event, not per attempt)

```
payment_id, merchant_code, merchant_name, provider_code,
occurred_at, settled_at, final_state, method, currency,
amount, fee_amount, net_amount, refunded_amount,
attempt_count, auth_to_capture_seconds,
-- date dimension key
date_key
```

The mistake to avoid: using the event as the grain. `payment.created`, `payment.succeeded`,
`payment.refunded` are three rows in Bronze. In Gold they are ONE row with `final_state = refunded`,
`refunded_amount = X`. Every aggregate query on payment facts should not need a CASE statement.

**`settlement_summary_daily`** — grain: one row per provider + currency + date

```
date, provider_code, currency, mode,
payment_count, gross_amount, provider_fees, platform_fees,
net_amount, reserve_held, variance
```

This is what the finance team reads every morning. It answers "did we receive what we expected
from each provider for each day?" Joining to `settlements` for the variance is the right
approach for Gold — do the join once in the transform, not on every dashboard load.

**`provider_health_hourly`** — grain: one row per provider + hour

```
provider_code, hour, method, currency, mode,
attempt_count, success_count, failure_count,
timeout_count, success_rate, p50_latency_ms, p95_latency_ms
```

This drives the Grafana dashboard. SLA monitoring needs hourly granularity — daily is too
coarse to detect an incident.

**`fee_margin_daily`** — grain: one row per merchant + day

```
merchant_code, day, currency, mode, fee_kind,
platform_fee_total, provider_cost_total, gross_margin, effective_rate_bps
```

The fee_kind split (`psp_margin` vs `orchestration_fee`) lets Model A and Model B revenue be
separated in reporting without a CASE statement in every query.

### Idempotency in the OLAP Transform

Bronze is append-only and may have duplicates (the worker retried, the event appeared twice).
Silver must deduplicate. The transform rule: `DISTINCT ON (event_id) ... ORDER BY event_id, _ingested_at ASC` — keep the earliest copy.

Gold must handle late-arriving data. A settlement report for Monday may arrive on Wednesday.
Strategy: **reprocess the affected partition** when late data arrives. Delete and rewrite the
`dt=` partition for the affected date. This requires that Gold transforms are idempotent:
running the same transform twice produces the same output. This means no auto-increment IDs
in Gold, no `now()` calls, no random values — deterministic from source data only.

### Star Schema for Gold (Not 3NF)

Gold is denormalised by design. The `merchant_name` is copied into `payment_facts` even though
it also exists in `dim_merchant`. Why? Because merchant names change. If you join live, a
merchant renamed six months ago makes all historical rows show the new name. Copying the name
at event time snapshots it.

This is **SCD Type 2** (Slowly Changing Dimension, Type 2): keep history by inserting new rows
rather than updating. For merchants: `{merchant_code, name, effective_from, effective_to}`.
Queries join on `merchant_code WHERE payment_date BETWEEN effective_from AND effective_to`.

**What needs SCD2 in Yagye:**
- Merchant legal/trading name
- Merchant risk rating (drives fee tier history)
- Provider fee schedule (what rate applied on a given day)

**What does NOT need SCD2:**
- Payment method (immutable on the payment)
- Currency (immutable)
- Mode (immutable)

### The Double-Entry Ledger in OLAP

The OLTP ledger has debit and credit rows — correct for OLTP, painful for OLAP. The Silver
transform for ledger data:

```sql
SELECT
  payment_id,
  merchant_code,
  SUM(CASE WHEN direction = 'credit' THEN amount ELSE -amount END) AS net_movement,
  currency,
  date_trunc('day', effective_at) AS day
FROM bronze_ledger_postings
GROUP BY payment_id, merchant_code, currency, date_trunc('day', effective_at)
```

Gold consumers never see raw ledger entries. They see net movements, pre-computed, keyed by
the same dimensions as `payment_facts` so joins are possible.

### What Is Missing from the OLAP Design

**No explicit Silver schema.** The Bronze schema (event envelopes) is defined. The Gold schema
(star schema grain) is discussed. The Silver intermediate — the per-entity state table with
typed columns — is implicit. It needs to be formally defined per domain before the Silver
transforms are built.

**No data quality rules.** Silver transforms should emit quality metrics: "how many rows were
rejected as null amounts," "how many events arrived more than 24h late," "how many payments
in Silver have no corresponding fee record." Without these, data quality degrades silently
and the Gold layer reports wrong numbers.

**No retention policy for Gold.** How long does `payment_facts` keep data? Bronze is
append-only forever (S3 is cheap). Gold at 10M payments/year with 50 columns is a few GB —
also cheap. But a formal retention policy, aligned with `retention_policies` in the OLTP
schema, should state: Gold data is kept for 7 years to match financial record requirements.

**DuckDB as the Gold query engine** is the right choice at P22 scale (< 10M payments/year).
At 100M payments/year, consider Apache Spark or Trino to parallelise the Silver→Gold transforms
across files. DuckDB is single-node and excellent; it is not a distributed query engine.
Plan the migration point, not the migration.
