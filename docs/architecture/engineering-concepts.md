# Engineering Concepts

**Last updated:** 2026-10-18

This document is for engineers who need to understand *why* Yagye is built
the way it is. Every section covers a specific decision — the problem it
solves, the alternative that was rejected, and how it is implemented in the
codebase. Nothing here is cargo-cult. Every choice has a cost and a reason.

Start with `docs/architecture/system-overview.md` first.

---

## Table of Contents

1. [Architectural Philosophy](#1-architectural-philosophy)
2. [Prefixed UUIDv7 Identifiers](#2-prefixed-uuidv7-identifiers)
3. [Integer Minor Units for Money](#3-integer-minor-units-for-money)
4. [Idempotency State Machine](#4-idempotency-state-machine)
5. [The Double-Entry Ledger](#5-the-double-entry-ledger)
6. [The Transactional Outbox](#6-the-transactional-outbox)
7. [Exactly-Once Event Processing](#7-exactly-once-event-processing)
8. [The Routing Engine](#8-the-routing-engine)
9. [Provider Adapter Pattern (ACL)](#9-provider-adapter-pattern-acl)
9b. [Portal Consumer ACL (Core Events → Portal Language)](#9b-portal-consumer-acl-core-events--portal-language)
10. [Payment Dispatch State Machine](#10-payment-dispatch-state-machine)
11. [Velocity Checking and Risk Tiers](#11-velocity-checking-and-risk-tiers)
12. [Webhook Delivery Pipeline](#12-webhook-delivery-pipeline)
13. [API Key Design and Security](#13-api-key-design-and-security)
14. [Cursor-Based Pagination](#14-cursor-based-pagination)
15. [Error Envelope and API Conventions](#15-error-envelope-and-api-conventions)
16. [Database-Backed RBAC](#16-database-backed-rbac)
17. [Portal as Read Model](#17-portal-as-read-model)
18. [Settlement and Reconciliation](#18-settlement-and-reconciliation)
19. [The Pricing Engine](#19-the-pricing-engine)
20. [Structured Logging and Observability](#20-structured-logging-and-observability)
21. [Concurrency and the BEAM](#21-concurrency-and-the-beam)
22. [OpenAPI-First Design](#22-openapi-first-design)
23. [Mode Isolation](#23-mode-isolation)
24. [No Hard Deletes and Audit Trails](#24-no-hard-deletes-and-audit-trails)
25. [Agentic API Surface](#25-agentic-api-surface)
26. [Oban Workers, Retry Logic, and Provider Failure Scenarios](#26-oban-workers-retry-logic-and-provider-failure-scenarios)
27. [Architecture Pattern — What Kind of System Is Yagye?](#27-architecture-pattern--what-kind-of-system-is-yagye)
28. [Why Not Event Sourcing, Commanded, or a Dedicated Event Store](#28-why-not-event-sourcing-commanded-or-a-dedicated-event-store)
29. [Message Brokers — Redpanda and RabbitMQ](#29-message-brokers--redpanda-and-rabbitmq)
30. [Event-Driven Architecture: Problems and How Yagye Resolves Them](#30-event-driven-architecture-problems-and-how-yagye-resolves-them)
31. [Database Architecture Decisions](#31-database-architecture-decisions)

---

## 1. Architectural Philosophy

### DDD-lite: the model we chose

Yagye uses Domain-Driven Design principles without adopting a full event-sourcing
framework. This is what "DDD-lite" means in practice:

- **Bounded contexts** — each domain (Payments, Merchants, Ledger, Routing,
  Settlement) is a separate Elixir context module with explicit public APIs.
  No context calls another context's private functions.
- **Domain events** — state changes produce events written to the outbox.
  Events are facts about the past, not commands.
- **Aggregates** — each Payment, Merchant, and Settlement is a root aggregate
  whose state is authoritative in one place (Core's write model).
- **No Commanded / Event Sourcing** — the aggregate state is stored as a current
  row in PostgreSQL, not as an event stream that must be replayed. This is a
  deliberate deferral. ES is expressive but operationally complex (snapshotting,
  event schema migrations, replay time). The outbox already publishes events;
  switching to full ES later is tractable.

The decision to defer Commanded is documented and not to be re-opened without
a concrete scaling or auditability requirement that DDD-lite cannot meet.

### The two-layer rule

```
┌─────────────────────┐
│    YagyeCoreWeb     │  Web layer: controllers, plugs, views
│  (lib/yagye_core_  │  Calls YagyeCore functions only.
│   web/)             │  Never touches schemas directly.
└──────────┬──────────┘
           │ calls
           ▼
┌─────────────────────┐
│    YagyeCore        │  Domain layer: contexts, schemas, changesets,
│  (lib/yagye_core/)  │  Oban workers.
└──────────┬──────────┘
           │ SQL
           ▼
┌─────────────────────┐
│    PostgreSQL       │
└─────────────────────┘
```

The reverse direction is banned. `YagyeCore` never imports anything from
`YagyeCoreWeb`. This is enforced at compile time by the `Boundary` library:
`YagyeCore` declares its allowed callers, and the compiler raises if any
module outside that set calls into it incorrectly.

Why this matters: web frameworks evolve. If a controller were allowed to query
the database directly, a "refactor the controller" task becomes entangled with
domain logic. The two-layer rule keeps the domain pure and web-layer-independent.

### Why not microservices?

At Yagye's current scale, a microservices split would add:

- Network latency on every cross-service call
- Distributed transaction complexity (two-phase commit or saga choreography)
- Separate CI pipelines, deployment cadences, and operational footprints
- Service discovery, circuit breakers, and health checks for internal calls

The BEAM (Erlang VM) gives us in-process concurrency with per-process fault
isolation. Oban gives us background job orchestration backed by PostgreSQL.
The outbox gives us inter-component event delivery without a broker until P14.

Phoenix's umbrella app pattern was also explicitly rejected (documented in
ADR architecture decisions). Umbrella apps share a build graph and are compiled
together — they are not separate services, so they provide a false sense of
isolation without the actual benefits.

The correct expansion path: carve out a service when a bounded context has a
measurably different scale or deployment requirement. Not before.

### DDD folder structure

Every domain context follows the same structure:

```
lib/yagye_core/
  payments/
    payments.ex          ← context (public API)
    schemas/
      payment.ex
      payment_attempt.ex
    commands/
      create_payment.ex
    events/
      payment_succeeded.ex
    workers/
      payment_dispatch_worker.ex
```

Module names mirror file paths. `YagyeCore.Payments.Schemas.Payment` lives in
`lib/yagye_core/payments/schemas/payment.ex`. This is a firm convention, not
a suggestion. Deviating from it means `mix xref` callers/callee analysis
breaks, and `Boundary` declarations become hard to maintain.

---

## 2. Prefixed UUIDv7 Identifiers

### The problem with opaque UUIDs

A standard UUIDv4 ID looks like `3f2c…`. Given a log line with a single ID,
you cannot know what kind of record it refers to without querying the database.
This slows down debugging and makes log analysis error-prone.

A sequential integer PK (`id: 12345`) is guessable. Enumerating
`GET /v1/payments/1`, `/2`, `/3` is a trivial API scraping attack. Integers
also impose a global ordering on creation, which is a subtle information leak.

### UUIDv7: time-ordered and random

UUIDv7 (RFC 9562) encodes a Unix millisecond timestamp in the first 48 bits,
followed by 74 bits of random data. This gives two properties:

1. **Lexicographic sort order = chronological creation order.** No separate
   `created_at` index is needed for `ORDER BY id`. This is crucial for the
   cursor-based pagination strategy (§14).

2. **B-tree friendly.** UUIDv4 inserts into a B-tree index at random positions,
   causing frequent page splits (the "UUID page-split problem"). UUIDv7 inserts
   near the rightmost leaf because new IDs are always larger than old ones.
   This dramatically reduces index fragmentation for high-write tables.

### The prefix convention

Every entity type has a two-to-four character prefix:

```
pay_018e…  → Payment
mch_018e…  → Merchant
cst_018e…  → Customer
inv_018e…  → Invoice
sbt_018e…  → SettlementBatch
lpst_018e… → LedgerPosting
lpky_018e… → IdempotencyKey
```

Prefixes are added at generation time by `Uniq.UUID`:

```elixir
defmodule YagyeCore.Payments.Schemas.Payment do
  use Ecto.Schema
  @primary_key {:id, Uniq.UUID, autogenerate: true, prefix: "pay"}
  ...
end
```

The `Uniq.UUID` type serialises to/from a prefixed string at the Elixir layer
but stores a raw 128-bit UUID in PostgreSQL. The prefix is display-only and
does not consume database storage.

### Safe to expose

Prefixed UUIDv7 IDs are the external IDs in API responses and URLs. They are:

- Not guessable from a known ID (74 bits of randomness)
- Not enumerable (uniform random component)
- Self-describing in logs (prefix tells you the entity type)
- Time-correlated but not time-precise (millisecond granularity, not nanosecond)

### The Uniq.UUID ON CONFLICT detection gotcha

Because `Uniq.UUID` pre-generates the ID before the `INSERT`, the result struct
from `Repo.insert(changeset, on_conflict: :nothing)` is always `{:ok, struct}`,
even when the insert was a no-op (conflict). The struct's `id` is the
pre-generated ID, not the conflicting row's ID.

The correct pattern after an idempotency-key insert is:

```elixir
{:ok, _} = Repo.insert(changeset, on_conflict: :nothing)
key = Repo.get_by(IdempotencyKey, merchant_id: mid, key: k)
# key is nil only if something went wrong. If non-nil, check key.state.
```

This is documented explicitly because the naive pattern — checking the `:ok`
return from `Repo.insert` — silently misses conflicts for UUID-primary-key tables.

---

## 3. Integer Minor Units for Money

### Why floating-point is forbidden

IEEE 754 double-precision floating-point cannot represent most decimal fractions
exactly. The canonical example:

```
0.1 + 0.2 = 0.30000000000000004
```

This is not a rounding error — it is the mathematically correct result of IEEE
754 addition. The issue is that `0.1` in binary is `0.0001100110011...` (a
repeating fraction), so it cannot be stored exactly in a finite number of bits.

In a ledger, this matters because:
- Summing 1000 small amounts in different orders produces different results.
- Comparing two computed amounts with `==` is unreliable.
- Distributing a total amount (e.g. splitting GHS 100 across 3 parties: GHS
  33.33 + GHS 33.33 + GHS 33.34) cannot be done correctly with floats — the
  cents get lost.

Financial institutions have been fined and faced regulatory action for
floating-point errors in ledgers. This is not a theoretical concern.

### The pesewa standard

All monetary amounts are stored as `bigint` in minor units:

```
GHS 100.00  = 10000 pesewas
GHS   0.50  =    50 pesewas
USD   1.99  =   199 cents
```

The `Yagye.Money` struct wraps a `{amount :: integer, currency :: atom}` pair.
All arithmetic operates on integers. Display formatting is the only place where
division or decimal arithmetic occurs, and it is strictly output-only — never
written back to the database.

`bigint` can hold up to 9,223,372,036,854,775,807, which is approximately
GHS 92 trillion. No realistic payment volume will overflow this.

### Largest-remainder allocation

When Yagye distributes a total amount across multiple parties and a rounding
remainder exists, it uses the largest-remainder method:

```
Total: GHS 100.00 (10000 pesewas)
Parties: 3

Ideal:   3333.33...   3333.33...   3333.33...
Floor:   3333         3333         3333         = 9999
Deficit: 1 pesewa

Sort by fractional part descending:  0.33 0.33 0.33  (tie — any wins)
Award the deficit to the first party: 3334 3333 3333  = 10000 ✓
```

This ensures the distributed amounts always sum to exactly the original total.
The naive approach (round each share) can produce totals that are 1–2 minor
units off, which the ledger's sum-zero invariant will reject at commit time.

---

## 4. Idempotency State Machine

### What it means in a PSP context

A payment API call is not a pure function — it moves money. If the call fails
mid-way (network timeout, process crash, provider latency spike) the client
does not know whether the charge was applied. Without idempotency, a retry
creates a duplicate charge.

This is not an edge case. Network failures happen constantly. A Ghanaian
merchant integration retrying a payment after a USSD timeout is the norm.
Idempotency is table stakes for any payment API.

### The `idempotency_keys` table

```
┌───────────────────────────────────────────────────────────┐
│                    idempotency_keys                        │
├───────────────────┬───────────────────────────────────────┤
│  id               │  UUIDv7 (prefixed)                    │
│  merchant_id      │  FK → merchants                       │
│  key              │  client-supplied (≤ 255 chars)        │
│  state            │  in_progress | completed | failed     │
│  request_fingerprint │ SHA-256(method + path + body)      │
│  response_status  │  HTTP status cached for replay        │
│  response_body    │  JSON cached for replay               │
│  lease_expires_at │  NOW() + 30s — crash protection       │
│  inserted_at      │  immutable creation timestamp         │
└───────────────────┴───────────────────────────────────────┘
UNIQUE (merchant_id, key)
```

The UNIQUE constraint on `(merchant_id, key)` means a key is merchant-scoped.
Merchant A and Merchant B can both use idempotency key `"order-123"` without
collision.

### The state machine

```
                                  ┌──────────────────────────────────────────┐
                                  │ Client sends request with Idempotency-Key │
                                  └──────────────────────────┬───────────────┘
                                                             │
                                  ┌──────────────────────────▼───────────────┐
                                  │  INSERT INTO idempotency_keys             │
                                  │  (merchant_id, key, state='in_progress',  │
                                  │   lease_expires_at = NOW() + 30s, ...)    │
                                  │  ON CONFLICT (merchant_id, key) DO NOTHING│
                                  └──────────────────────────┬───────────────┘
                                                             │
                              ┌──────────────────────────────▼───────────────┐
                              │  Fetch row from DB (required: Uniq.UUID issue) │
                              └──────────┬────────────────┬──────────────────┘
                                         │                │
                              ┌──────────▼──────┐ ┌───────▼──────────────────┐
                              │ No conflict      │ │ Conflict found           │
                              │ → process request│ └──────┬───────────────────┘
                              └──────────┬───────┘        │
                                         │         ┌──────▼────────────────┐
                                         │         │ state = in_progress?  │
                                         │         └──────┬────────────────┘
                                         │                │
                                         │       ┌────────▼──────────────┐
                                         │       │ lease_expires_at > now │
                                         │       │ → 409 Conflict        │
                                         │       │ lease expired          │
                                         │       │ → re-claim (retry safe)│
                                         │       └───────────────────────┘
                                         │
                              ┌──────────▼────────────────────┐
                              │ state = completed              │
                              │ → replay response_body + code │
                              │                               │
                              │ state = failed                 │
                              │ → 422 "previous attempt failed"│
                              │   (client must use new key)   │
                              └───────────────────────────────┘
```

The claim is inserted **before** execution begins. If the process crashes
mid-execution, the `lease_expires_at` timestamp provides crash recovery: after
30 seconds, another request for the same key can re-claim it rather than
waiting forever.

### The request fingerprint

`request_fingerprint` is `SHA-256(method + path + raw_body)`. If a client
sends the same idempotency key with a **different** request body (e.g. changed
the amount), Core returns a `400 Bad Request` — the key has already been
claimed for a different request. This prevents silent re-use of a key with
mutated parameters.

### Why not Redis (SETNX)?

1. **Not durable.** A Redis restart or eviction loses in-flight keys. A retry
   after restart re-claims a key and executes the operation twice.
2. **Not atomic with the operation.** Redis and PostgreSQL are separate stores.
   If the payment commits but the Redis SET fails, the key is lost. The next
   retry creates a duplicate.
3. **Not auditable.** Redis provides no queryable history of claimed keys and
   returned responses. Regulators require this history.

The PostgreSQL approach stores the idempotency key **in the same transaction**
as the payment record. Atomicity and durability are inherited from the DB.

### AI agent protection

ADR-0024 notes that LLM-powered tool-use loops may call `POST /v1/payments`
multiple times for the same intent because the model hallucinated a failure.
The idempotency key prevents this — the client SDK sends the same key on
retries. The PSP handles the rest. This is a first-class design concern, not
an afterthought. See §25 for the full agentic API discussion.

### Provider idempotency

When a provider callback arrives at `POST /provider-webhooks/:code`, Core
always returns 200 after HMAC verification — even if downstream processing
fails. The provider retries non-2xx responses. If the database write succeeded
but the HTTP response was lost (common with MoMo USSD callbacks), the retry
would arrive with the same transaction reference.

Core's webhook handler uses the provider's transaction reference as an
idempotency key on the `payment_attempts` table. A duplicate callback finds
the attempt already in `succeeded` state and skips the state transition cleanly.

---

## 5. The Double-Entry Ledger

### Why double-entry? The accounting argument

Double-entry bookkeeping has been the standard for financial accounting since
Luca Pacioli formalised it in 1494. Every regulated financial institution uses
it for one reason: it is self-auditing.

In a single-entry system, a balance is a running number that gets incremented
and decremented. A bug that corrupts the balance leaves no way to reconstruct
the correct value — the history is gone.

In a double-entry system, **every money movement is recorded as two entries**:
one debit and one credit of equal magnitude. The sum of all debits always equals
the sum of all credits (the sum-zero invariant). Any discrepancy is immediately
detectable, and any balance can be recomputed from scratch by replaying the
posting rows.

This is not gold-plating. PSP regulations require reconstructible audit trails.
The double-entry structure is the audit trail.

### Account types in Yagye

```
┌─────────────────────────────────────────────────────────────┐
│                      LEDGER ACCOUNTS                         │
├────────────────────┬────────────────────────────────────────┤
│  float_account     │  Yagye's MoMo/bank float holdings      │
│  merchant_payable  │  Funds owed to a specific merchant     │
│                    │  (post-fee deduction)                  │
│  fee_payable       │  Yagye's accrued platform fees         │
│  reserve_account   │  Withheld rolling reserve (risk buffer)│
│  bank_payable      │  Funds staged for bank wire transfer   │
│  provider_payable  │  Amounts owed back to providers        │
│  suspense          │  Unreconciled amounts (temporary only) │
└────────────────────┴────────────────────────────────────────┘
```

Each posting records: account, direction (debit/credit), amount (bigint),
currency, timestamp, and the originating transaction reference.

### A payment: how money flows through the ledger

When a customer pays GHS 100 to a merchant (Yagye's fee: GHS 2.80):

```
Event: payment.succeeded — GHS 100.00 (10000 pesewas)

Phase 1: MoMo callback confirms funds received
  DEBIT   suspense            10000
  CREDIT  float_account       10000
  [MoMo settlement is not instant — suspense holds until confirmed]

Phase 2: Funds allocated
  DEBIT   float_account       10000
  CREDIT  merchant_payable     9720   (GHS 97.20 net to merchant)
  CREDIT  fee_payable           280   (GHS 2.80 Yagye fee)

Sum check:  DEBITS (10000 + 10000) = CREDITS (10000 + 9720 + 280) ✓
```

### Settlement: merchant_payable → bank

```
Event: settlement_batch.sweep_initiated
  DEBIT   merchant_payable    9720
  CREDIT  bank_payable        9720   (staged for bank wire)

Event: settlement_batch.disbursed
  DEBIT   bank_payable        9720
  CREDIT  float_account       9720   (float reduced by payout)

Running total after full cycle:
  float_account:      +10000 - 10000 - 9720 + 9720 = 0  (net zero)
  merchant_payable:   +9720  - 9720                 = 0
  fee_payable:        +280                           = +280 (Yagye's revenue)
```

### The sum-zero invariant trigger

The `ledger_postings` table has a deferred constraint trigger that fires at
`COMMIT` time (not per-row, because both sides of an entry land in the same
transaction):

```sql
CREATE CONSTRAINT TRIGGER assert_sum_zero
  AFTER INSERT ON ledger_postings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION check_entry_sum_zero();
```

The trigger function:

```sql
SELECT SUM(
  CASE WHEN direction = 'debit' THEN amount ELSE -amount END
) FROM ledger_postings
WHERE entry_id = NEW.entry_id;
-- Must equal 0. Raises exception otherwise, aborting the transaction.
```

This makes it structurally impossible to commit an unbalanced entry. Even a
developer running raw SQL in a migration cannot accidentally corrupt the ledger
without the trigger catching it.

### Why `ledger_postings.id` is a bigserial, not a UUID

Every other entity uses prefixed UUIDv7. The exception is `ledger_postings`:

```
id bigserial  -- dense, ordered, never exposed, last_posting_id is a watermark
```

Reasons:

1. **Dense integers enable watermarking.** The `ledger_balances` cache stores
   `last_posting_id bigint`. This is a meaningful watermark: the balance is
   provably correct for all postings with `id <= last_posting_id`. A UUID
   watermark would require a separate timestamp column, which has millisecond
   granularity and cannot handle same-millisecond ordering.

2. **Never exposed.** Posting IDs are never in API responses or URLs. The
   prefix-for-readability argument does not apply to internal accounting records.

3. **B-tree performance.** High-volume insert tables benefit from sequential
   integer PKs — no page splits, no index bloat.

### `ledger_balances` is a cache, not truth

```sql
ledger_balances
  account_id        uuid
  balance           bigint
  last_posting_id   bigint    ← the watermark
```

The balance can always be recomputed as:

```sql
SELECT SUM(
  CASE WHEN direction = 'credit' THEN amount ELSE -amount END
) FROM ledger_postings
WHERE account_id = $1;
```

`ledger_balances` caches this sum for query speed. Its correctness is
provable: if `last_posting_id = 42`, then `balance = SUM(postings WHERE id <= 42)`.
Any posting with `id > 42` was not included. This allows the cache to be
updated incrementally without a full recount.

### Append-only enforcement

```sql
-- The application role is revoked UPDATE and DELETE on ledger_postings:
REVOKE UPDATE, DELETE ON ledger_postings FROM yagye_core_app;
```

Corrections are made via reversing entries — a new posting pair that inverts
the original. The original incorrect postings remain in the audit trail. This
is standard accounting practice and a regulatory requirement.

### Bitemporal timestamps on `ledger_entries`

Each ledger entry has two timestamps:

- `effective_at` — the domain date (when the payment was made, as the merchant sees it)
- `recorded_at` — the system date (when the DB row was inserted)

For normal operations, these are the same. For backdated corrections (a
provider confirms a payment from yesterday), `effective_at` is yesterday and
`recorded_at` is now. This enables correct reporting across arbitrary date
ranges without special-casing corrections.

---

## 6. The Transactional Outbox

### The dual-write problem

Naive event publishing:

```
1. UPDATE payments SET state = 'succeeded'  -- commits
2. publish("payment.succeeded") to Redpanda -- may fail
```

If the process crashes between steps 1 and 2: the payment is `succeeded` but
no event was published. Downstream systems never learn about it.

Reversed order:

```
1. publish("payment.succeeded") to Redpanda  -- commits
2. UPDATE payments SET state = 'succeeded'   -- may fail
```

Now an event exists for a payment that is not `succeeded`. Downstream systems
process a phantom event.

There is no distributed transaction that atomically spans a relational database
and a message broker. This is a fundamental constraint of distributed systems.
The outbox pattern is the standard solution.

### The outbox solution

Write the event row into a table **in the same database**, **in the same transaction**
as the state change:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:payment, Payment.succeed_changeset(payment))
|> Ecto.Multi.insert(:ledger_dr, LedgerPosting.debit_changeset(...))
|> Ecto.Multi.insert(:ledger_cr, LedgerPosting.credit_changeset(...))
|> Ecto.Multi.insert(:outbox, OutboxMessage.build("payment.succeeded", payload))
|> Repo.transaction()
```

All four writes commit atomically. If any fails, all roll back. The event row
is guaranteed to exist if and only if the state change committed.

### The `outbox_messages` table

```
┌───────────────────────────────────────────────────────────────┐
│                       outbox_messages                          │
├──────────────────────┬────────────────────────────────────────┤
│  id                  │  bigserial — efficient sequential scan │
│  event_id            │  text UNIQUE (ULID) — consumer dedup  │
│  event_type          │  "payment.succeeded"                   │
│  aggregate_type      │  "payment"                             │
│  aggregate_id        │  the entity's UUID                     │
│  aggregate_version   │  monotonic version for fencing         │
│  partition_key       │  text (merchant_id for ordering)       │
│  destination         │  text — DATA, not code                 │
│  envelope            │  jsonb — full event payload            │
│  mode                │  yagye_mode (simulation/sandbox/live)  │
│  published_at        │  timestamptz NULL — until relayed      │
│  publish_attempts    │  integer — alert on stuck events       │
└──────────────────────┴────────────────────────────────────────┘
```

The `destination` field is **data, not code**. Today it might be
`"internal:projections"`. At P14, it becomes `"redpanda:payment.events"`.
Changing the delivery target requires a data migration, not a code change.

The `event_id` is a ULID (not a UUID): lexicographically sortable, with 10ms
precision, 80 bits of random data. It serves as the consumer deduplication key
in the `processed_events` table (§7).

### The relay worker

```elixir
defmodule YagyeCore.Outbox.OutboxRelayWorker do
  use Oban.Worker, queue: :outbox, max_attempts: 10

  def perform(_) do
    OutboxMessage
    |> where([m], is_nil(m.published_at))
    |> order_by([m], asc: m.id)
    |> limit(100)
    |> Repo.all()
    |> Enum.each(&dispatch/1)
  end
end
```

The `ORDER BY id` scan uses the bigserial PK efficiently — it is a sequential
scan from the last processed row, not a full table scan. At high volume, the
relay can be partitioned by `destination` or `partition_key`.

### Why not Kafka Transactions?

Kafka Transactions (`transactional.id`) provide exactly-once semantics
within Kafka. But they do not span Kafka and PostgreSQL. You still commit the
state change to Postgres and then begin the Kafka transaction — the dual-write
problem is unsolved.

The outbox is simpler, fully observable (the table is queryable), and does not
require Kafka broker tuning. The relay can be replaced by a Kafka producer at
P14 without changing the outbox schema or the consumer deduplication logic.

---

## 7. Exactly-Once Event Processing

### The at-least-once guarantee and why it is unavoidable

No reliable message broker guarantees exactly-once delivery. Redpanda
(Kafka-compatible) guarantees at-least-once. After a consumer commits an
offset, the broker considers the message delivered. If the consumer crashes
after processing but before committing the offset, the message is redelivered
on reconnection. The consumer sees it twice.

This is expected and correct behaviour. The burden of exactly-once semantics
falls on the consumer.

### Strategy 1: Version fencing for entity state projections

For projections that track the current state of an entity (payment status,
merchant status), replaying an event is safe as long as an older version
cannot overwrite a newer one:

```sql
INSERT INTO portal_payments (core_payment_id, status, aggregate_version, ...)
VALUES ($1, $2, $3, ...)
ON CONFLICT (core_payment_id) DO UPDATE
  SET status             = EXCLUDED.status,
      aggregate_version  = EXCLUDED.aggregate_version,
      updated_at         = EXCLUDED.updated_at
  WHERE portal_payments.aggregate_version < EXCLUDED.aggregate_version;
```

The `WHERE` clause makes the update a no-op for stale events. A redelivered
event with `aggregate_version: 3` cannot overwrite a row that already has
`aggregate_version: 5`. The state is at most slightly stale during the
redelivery window — never corrupted.

### Strategy 2: `processed_events` for counter projections

Version fencing cannot protect counter (additive) projections. Consider:

```
payment.succeeded → ADD GHS 100 to merchant's available balance
```

This is not idempotent. Replaying it adds GHS 100 a second time. The
`processed_events` table solves this:

```sql
processed_events
  event_id   text   ─┐ composite primary key
  consumer   text   ─┘
  processed_at timestamptz
```

Before any counter update:

```sql
INSERT INTO processed_events (event_id, consumer, processed_at)
VALUES ($1, $2, NOW())
ON CONFLICT DO NOTHING
RETURNING *;
```

If the insert returns 1 row: process the event. If it returns 0 rows: the
event was already processed — skip. The `ON CONFLICT DO NOTHING` is atomic:
two concurrent consumers racing on the same event cannot both succeed.

A nightly sweep removes rows older than 30 days. Redpanda's retention window
is configured to be longer than the sweep interval, so no event older than 30
days will be redelivered.

### The compound guarantee: outbox + idempotent consumer

```
Outbox ensures:  event exists ↔ state change committed
                 (no phantom events, no lost events)

Version fencing ensures:  stale state projections are no-ops
processed_events ensures: counter projections are not double-counted

Result:  effectively-once semantics despite at-least-once delivery
```

"Effectively once" is the practical standard. True exactly-once (a single
delivery with zero duplicates) would require coordination that is more expensive
than the occasional duplicate that idempotent consumers silently discard.

### Visualised: dedup state machine

```
Consumer receives event_id = "01JKLM..."
         │
         ▼
INSERT INTO processed_events (event_id, consumer)
ON CONFLICT DO NOTHING
         │
    ┌────┴─────┐
    │           │
 1 row       0 rows
affected     affected
    │           │
    ▼           ▼
Process      Skip
event        (already processed)
    │
    ▼
UPDATE portal_merchant_balances
WHERE aggregate_version < incoming_version
    │
    ▼
Commit Redpanda offset
```

### Why Redpanda (not RabbitMQ) for internal events?

RabbitMQ is used for outbound merchant webhooks (§12). The distinction is ordering.

Redpanda partitions are totally ordered: events for a given `merchant_id`
routed to the same partition arrive in the order they were produced. This is
critical for version fencing — you cannot receive `aggregate_version: 5`
before `aggregate_version: 4` from the same partition.

RabbitMQ does not guarantee ordering across concurrent consumers. Using it
for event streaming would require the consumer to sort events by version before
applying them — complex, fragile, and unnecessary when Redpanda provides the
guarantee natively.

---

## 8. The Routing Engine

### The problem: choosing the right provider

A payment in Ghana involves multiple providers: MTN MoMo GH, Vodafone Cash,
AirtelTigo Money, and eventually Stripe (cards). The routing engine selects
the correct provider for each payment.

**Critical constraint:** For mobile money, the customer's MSISDN unambiguously
determines the network. An MTN MSISDN can only be charged via MTN MoMo. A
Vodafone MSISDN can only be charged via Vodafone Cash. There is no cross-network
fallback — MoMo rails do not support it. Provider selection for MoMo is therefore
MSISDN-deterministic; the routing engine finds the active rule that matches the
detected network. For card payments (Stripe), routing is merchant/currency-based.

The decisions that remain non-trivial:

- Which active rule matches this MSISDN's network and the payment currency?
- If multiple aggregator paths exist for the same network, which has better health?
- Is this provider's circuit breaker open (skip and fail fast)?
- A merchant may override the platform rule with their own routing configuration.
- Enterprise merchants (Model B, P16+) build their own routing rules visually.

### Routing rules: the data model

```sql
routing_rules
  id                    uuid PK
  merchant_id           uuid NULL  -- NULL = platform-wide rule
  scope                 text       -- 'platform' | 'merchant'
  provider_code         text       -- 'mtn_momo_gh', 'stripe', ...
  payment_method_type   text       -- 'mobile_money', 'card', ...
  currency              text       -- 'GHS', 'USD', ...
  network_code          text NULL  -- 'mtn', 'vodafone', ...
  priority              integer
  is_active             boolean
  routing_configuration_id uuid NULL  -- FK to visual builder config
```

Two partial unique indexes enforce that a platform rule and a merchant rule
with the same parameters coexist without conflict:

```sql
-- Platform rules (merchant_id IS NULL)
CREATE UNIQUE INDEX routing_rules_platform_unique
  ON routing_rules (scope, provider_code, payment_method_type, currency, network_code)
  WHERE merchant_id IS NULL;

-- Merchant rules (merchant_id IS NOT NULL)
CREATE UNIQUE INDEX routing_rules_merchant_unique
  ON routing_rules (merchant_id, scope, provider_code, payment_method_type, currency, network_code)
  WHERE merchant_id IS NOT NULL;
```

`NULLS DISTINCT` is the default PostgreSQL behaviour: two NULLs in a unique
index are considered distinct, which would allow duplicate platform rules with
NULL `network_code`. The partial index workaround — two separate indexes, each
covering only one scope — eliminates this ambiguity.

### Resolution algorithm

```
Given: payment with currency=GHS, method=mobile_money, network=mtn

1. Load merchant-scope rules for this merchant, filtered by:
   - currency matches or is NULL
   - payment_method_type matches or is NULL
   - network_code matches or is NULL
   ORDER BY priority ASC, specificity DESC

2. If no merchant rule matches, load platform-scope rules with same filters.

3. Take the first matching rule. If none match: reject with no_route_available.
```

The `specificity` column is a precomputed integer: the count of non-null
filter columns. A rule that matches `currency + method + network` has
specificity 3. A rule that matches only `method` has specificity 1. The
most specific matching rule wins, ensuring that targeted rules take precedence
over catch-all rules.

### Visual routing builder (Drawflow)

Merchants configure routing rules via a visual node graph editor in the portal.
The graph editor is built with **Drawflow** (v0.0.59, loaded from CDN) — a
lightweight JavaScript drag-and-drop flow library. It is driven by a Stimulus
controller (`routing_graph_controller.js`) with no React or heavy framework
dependency.

**Node vocabulary (v1):**

| Node | Colour | Inputs | Outputs | Purpose |
|---|---|---|---|---|
| `ProviderNode` | Green | 1 | 1 | Route to a specific payment provider |
| `ConditionNode` | Amber | 1 | 2 | Branch on a field value (output_1 = match, output_2 = no match) |
| `SplitNode` | Blue | 1 | 2 | Percentage traffic split — **cards and bank only** |
| `FallbackNode` | Grey | 1 | 1 | Retry with same-method provider on failure — **cards and bank only** |
| `SimulatorNode` | Grey | 1 | 1 | Dev/staging only — rejected by Core if published |

**Critical constraint carried into the node vocabulary:**
`SplitNode` and `FallbackNode` explicitly note "cards/bank only — not between
mobile networks." A MoMo MSISDN is locked to exactly one network; rerouting
it to a different provider is impossible. The node picker UI surfaces this
constraint in the node description text so merchants cannot build an invalid
graph.

**ConditionNode fields:** `network`, `currency`, `amount`, `method`, `country`,
`card_brand`, `card_funding`, `risk_score`. Operators: `eq`, `neq`, `gt`,
`gte`, `lt`, `lte`, `in`, `not_in`.

**Built-in templates:**
- **Network routing** — three ConditionNode→ProviderNode pairs, one per Ghana
  mobile network (MTN, Telecel, AirtelTigo). Each MSISDN prefix maps to exactly
  one network; each condition is a precise match, not an "else" fallback.
- **Traffic split** — SplitNode feeding two ProviderNodes. Labelled for
  card/bank use only.
- **Network filter** — single ConditionNode→ProviderNode pair as a starting
  point; the no-match output is left unconnected so unmatched payments fall
  through to the static priority fallback.

**Save and publish flow:**
The Stimulus controller serialises the Drawflow graph into a normalised
`graph_payload` JSON (`{ nodes, edges, schema_version: 1 }`) and submits it
to Portal's `routing_rules` controller. Portal sends it to Core via the API.
Core stores it in `routing_configurations.graph_payload` and, on publish,
compiles it into active `routing_rules` rows.

**Audit trail:**
`payment_attempts.routing_configuration_id` records which published
configuration was active at dispatch time. This creates an immutable audit
trail — any routing decision can be replayed by looking up the configuration
that was live at that timestamp.

---

## 9. Provider Adapter Pattern (ACL)

### The anti-corruption layer

Each external provider (MTN MoMo, Stripe, Flutterwave, Paystack) has a
different API shape, webhook format, and authentication scheme. Without a
systematic abstraction, provider-specific details leak throughout the codebase.
Adding a new provider requires changes in many places. Removing a provider
requires tracking down every reference.

The provider adapter is an Anti-Corruption Layer (ACL, from DDD terminology):
a boundary that translates between the provider's external representation and
Yagye's internal domain model.

### The adapter contract

Every provider adapter implements five functions:

```elixir
@callback charge(provider_config, payment_params, opts) ::
  {:ok, ProviderResponse.t()} | {:error, ProviderError.t()}

@callback void(provider_config, payment_attempt, opts) ::
  {:ok, VoidResponse.t()} | {:error, ProviderError.t()}

@callback refund(provider_config, payment, refund_params, opts) ::
  {:ok, RefundResponse.t()} | {:error, ProviderError.t()}

@callback verify_webhook(provider_config, headers, raw_body) ::
  :ok | {:error, :invalid_signature}

@callback parse_webhook(provider_config, headers, body) ::
  {:ok, WebhookEvent.t()} | {:error, :unknown_event_type}
```

The rest of Core (dispatch, settlement, reconciliation) knows nothing about
HTTP headers, HMAC algorithms, or JSON field names. It calls the adapter and
receives a typed struct.

### The gateway_simulator as development ACL

In development and CI, all providers resolve to `GatewaySimulator`, an Elixir
Phoenix application that speaks the same HTTP protocol as real providers:

```
X-Simulator-Outcome: success     → simulate a successful charge
X-Simulator-Outcome: timeout     → simulate a provider timeout
MSISDN: 024 100 0002             → fixed MSISDN map → insufficient_funds
```

This means Core's provider adapters are exercised against real HTTP
round-trips, not mocks. Req.Test unit tests cover the adapter's HTTP request
construction and response parsing at the unit level. The simulator covers
end-to-end dispatch behaviour. Real sandbox credentials are used for
integration testing against provider sandboxes (manually, not in CI).

### Error classification

Provider errors are classified into four categories that drive the payment
state machine (§10):

```
definite_failure    — provider confirmed the charge failed (e.g. insufficient_funds)
                      Retry will not succeed. Mark payment failed.

retryable_error     — provider returned a transient error (e.g. 503, timeout)
                      Retry with exponential backoff.

indeterminate       — the request timed out and no callback arrived
                      Cannot know if the charge was applied.
                      Enter resolution_pending state; wait for reconciliation.

invalid             — the request was malformed (e.g. invalid MSISDN format)
                      Return 422 to the merchant immediately.
```

The `payment_attempts.error_class` column stores this classification. It drives
whether a retry is scheduled, whether reconciliation is triggered, and what
error code is returned to the merchant.

---

## 9b. Portal Consumer ACL (Core Events → Portal Language)

The Anti-Corruption Layer pattern appears twice in Yagye for two completely
different reasons.

**§9 (Provider ACL)** protects Core from external provider chaos. MTN MoMo's
API shape — its error codes, field names, timestamp formats — cannot bleed into
Core's domain model. The adapter translates at the boundary.

**§9b (Portal Consumer ACL)** protects Portal from Core's internal language.
Core uses state-machine terminology, internal identifiers, and Elixir-shaped
JSON payloads. If Portal's Karafka consumers and projection workers directly
read `payload["state"]` and `payload["public_id"]`, then Core's internal naming
choices become a bilateral contract. Renaming a Core field would break the
Portal consumer silently.

The ACL class (a plain Ruby object, not a model) translates inbound Core event
payloads into Portal's own vocabulary before any projection logic touches them.
All consumers go through it — no consumer reads raw payload fields directly.

### Real translations from the codebase

| Core field / value | Portal ACL output | Reason |
|---|---|---|
| `state: "succeeded"` | `status: "paid"` | Core records a state-machine transition; Portal shows a customer-facing label |
| `state: "chargebacked"` | `status: "refunded"` | Portal collapses two Core states into one display state |
| `method: "card"` | `payment_method: "card"` | Avoid collision with Ruby's built-in `Object#method` |
| `public_id: "pay_018e..."` | `core_payment_id: "pay_018e..."` | Portal's own primary key is different; the Core ID is a reference, not the PK |
| `merchant_public_id: "mch_..."` | `merchant_code: "mch_..."` | Portal normalises key names to its own convention |
| `mode: "sandbox"` or `mode: "simulation"` | `mode: "test"` | Core has two non-live modes; Portal normalises to one for display |
| `inserted_at` (Elixir) | `created_at` (Rails) | Each app uses its framework's convention — translation happens at the ACL boundary |

### Why this matters

Without the consumer ACL:
- A Core field rename (e.g. `public_id` → `payment_ref`) silently breaks every
  Portal query that filters on the old name — no compile-time error, no test
  failure until a consumer processes a new event
- Core's internal state names appear in the Portal UI layer, coupling UI labels
  to internal state machine terminology
- Rails model callbacks operate on `state` (Elixir convention) mixed with
  Rails' own `status` — a developer cannot tell which system's vocabulary they
  are looking at

With the ACL:
- One file changes when Core renames a field. Projection workers and query
  objects are unaware.
- Core's state machine can evolve (new intermediate states) without Portal
  knowing — the ACL maps new states to existing display states until Portal is
  ready to introduce a new one.
- A new Core event field is opt-in: the ACL exposes it only when Portal is
  ready to use it.

### The ACL is not a model

The consumer ACL is a plain Ruby object with no ActiveRecord dependency. It
takes a raw payload hash and returns a normalised hash (or raises if a required
field is missing). This makes it unit-testable without a database connection —
the single most important class to test in the projection pipeline.

```ruby
class CoreEventACL
  def self.normalize_payment(payload)
    {
      core_payment_id:  payload.fetch("public_id"),
      merchant_code:    payload.fetch("merchant_public_id"),
      status:           translate_state(payload.fetch("state")),
      payment_method:   payload.fetch("method"),
      amount_minor:     payload.fetch("amount"),
      currency:         payload.fetch("currency"),
      mode:             normalize_mode(payload.fetch("mode")),
      created_at:       Time.parse(payload.fetch("inserted_at"))
    }
  end

  private

  def self.translate_state(core_state)
    {
      "succeeded"        => "paid",
      "failed"           => "failed",
      "chargebacked"     => "refunded",
      "pending_provider" => "processing"
    }.fetch(core_state, core_state)  # pass through unknown states — alert on nil later
  end

  def self.normalize_mode(core_mode)
    core_mode.in?(%w[sandbox simulation]) ? "test" : core_mode
  end
end
```

### Contrast with the Provider ACL

| | Provider ACL (§9) | Portal Consumer ACL (§9b) |
|---|---|---|
| **Protects** | Core from provider API chaos | Portal from Core's internal vocabulary |
| **Direction** | Inbound: provider HTTP → Core domain | Inbound: Core event payload → Portal model |
| **Implementation** | ProviderAdapter behaviour (Elixir protocol) | Plain Ruby class (no ActiveRecord) |
| **When it runs** | At the provider webhook controller | In each Karafka consumer before projection |
| **Failure mode** | Provider changes their API shape | Core renames an internal field |
| **Test strategy** | Req.Test HTTP-level unit tests | Plain unit test on the ACL class |

Both are Anti-Corruption Layers. The name describes the role — preventing one
system's internal language from corrupting another system's model — not the
technology.

---

## 10. Payment Dispatch State Machine

### Why an explicit state machine?

A payment is not a single operation — it is a lifecycle with multiple actors
(merchant, provider, reconciliation job), multiple failure modes, and timing
dependencies (provider callbacks may arrive seconds or minutes after dispatch).

Without an explicit state machine, payment status becomes implicit in a
collection of boolean flags and nullable timestamps. Bugs emerge when two
transitions race: two concurrent callbacks both attempt to mark a payment
`succeeded`. The state machine, enforced by PostgreSQL, prevents this.

### The `payment_attempts` state machine

```
                   ┌──────────┐
  dispatch called  │          │
 ─────────────────►│ created  │
                   │          │
                   └────┬─────┘
                        │ HTTP request sent to provider
                        ▼
                   ┌──────────┐
                   │dispatched│
                   └────┬─────┘
                        │
            ┌───────────┼───────────────┐
            │           │               │
            ▼           ▼               ▼
       ┌─────────┐ ┌─────────┐ ┌──────────────────┐
       │succeeded│ │ failed  │ │ resolution_pending│
       └─────────┘ └─────────┘ └────────┬─────────┘
                                         │
                                   (timeout, no callback)
                                         │
                              ┌──────────▼──────────┐
                              │  reconciliation job  │
                              │  queries provider    │
                              └──────────┬──────────┘
                                         │
                              ┌──────────▼──────────┐
                              │timed_out | abandoned │
                              │ or loops back to     │
                              │ succeeded/failed     │
                              └─────────────────────┘
```

Key states:

- `created` — attempt record written; HTTP not yet sent
- `dispatched` — HTTP sent; awaiting callback
- `succeeded` — provider confirmed charge succeeded
- `failed` — provider confirmed charge failed (definitively)
- `resolution_pending` — HTTP timed out; callback not yet received
- `timed_out` — reconciliation confirmed no charge was applied
- `abandoned` — maximum retries exhausted; manual review required

### The `idempotency_token` on `payment_attempts`

```sql
payment_attempts.idempotency_token text
```

This is Yagye's token sent **to the provider**, not the merchant's idempotency
key. When dispatching a charge, Core generates a unique token and sends it in
the provider's idempotency header (e.g. `Idempotency-Key` for Stripe,
`X-Correlation-ID` for MoMo). If the dispatch request times out, the token
allows Core to later query the provider: "Did the charge with token X succeed?"

This is the mechanism that resolves `resolution_pending` states during
reconciliation sweeps.

### The `routing_configuration_id` audit trail

Every `payment_attempts` row stores the `routing_configuration_id` that was
active when it was dispatched. This is immutable — changing routing rules after
a payment does not affect the historical record. Post-hoc analysis can answer:
"Was this payment affected by the routing rule change on date X?" without
time-traveling through configuration history.

---

## 11. Velocity Checking and Risk Tiers

### What velocity checking is

Velocity checking limits the volume of transactions within a time window. For
a PSP, it serves two purposes:

1. **Fraud prevention.** A compromised merchant account cannot be used to
   process unlimited fraudulent charges before detection.
2. **Risk management.** Yagye's float account has finite capacity. Merchants
   with large transaction volumes must be explicitly approved for higher limits.

### The `velocity_limits` table

```sql
velocity_limits
  entity_type  text   -- 'merchant' | 'customer'
  risk_tier    text   -- merchant: low/medium/high; customer: tier_1/tier_2/tier_3
  window_seconds integer
  max_amount   bigint   -- in minor units
  max_count    integer
  currency     text
```

Limits are tiered by risk profile. A `high`-risk merchant has lower limits
than a `low`-risk merchant. A `tier_1` customer (unverified KYC) has much
lower limits than a `tier_3` customer (full KYB passed).

If no seed row exists for a given `(entity_type, risk_tier)` combination, Core
falls back to hardcoded defaults defined in the Elixir application config. This
prevents a missing database row from disabling velocity checking entirely — a
security invariant.

### Checking algorithm

```elixir
def check_velocity(merchant_id, customer_id, amount, currency) do
  limits = fetch_limits_from_db(merchant_id_risk_tier, customer_id_risk_tier)

  merchant_window_total = sum_attempts_in_window(merchant_id, limits.merchant.window_seconds)
  customer_window_total = sum_attempts_in_window(customer_id, limits.customer.window_seconds)

  cond do
    merchant_window_total + amount > limits.merchant.max_amount ->
      {:error, :merchant_velocity_exceeded}
    customer_window_total + amount > limits.customer.max_amount ->
      {:error, :customer_velocity_exceeded}
    true ->
      :ok
  end
end
```

The check runs within the payment creation transaction, before dispatch. A
velocity breach returns a `422` immediately, without creating a payment record
or consuming an idempotency key slot.

### KYC tiers and velocity

Customer risk tiers (`tier_1`, `tier_2`, `tier_3`) are set by the KYC
verification result. Real provider APIs return a `kyc_tier` field; if nil,
the customer stays at `tier_1`. Velocity limits for each tier are configured
in `velocity_limits`, not hardcoded in business logic. This allows compliance
to tune limits without a code deployment.

---

## 12. Webhook Delivery Pipeline

### What merchant webhooks are

When a payment succeeds, the merchant's system needs to know — not just
via a polling API, but via a push notification to a URL they configured.
This is a webhook: an outbound HTTP POST from Yagye to the merchant's server.

Webhook delivery is fundamentally unreliable: the merchant's server may be
down, slow, or returning errors. Yagye must handle retries, backoff, and
eventual failure without losing delivery records or blocking payment processing.

### Architecture: RabbitMQ + Broadway + Oban

```
Core: payment.succeeded event
         │
         ▼
Oban: WebhookFanoutWorker
  For each enabled endpoint subscribed to this event type:
    Publish to RabbitMQ exchange: "webhooks.delivery"
         │
         │ (per-merchant queue via binding key)
         ▼
RabbitMQ: per-merchant queue (e.g. "webhooks.mch_018e...")
  Dead-letter exchange: "webhooks.dlx"
         │
         ▼
Portal: Broadway consumer (Karafka for Redpanda / BroadwayRabbitMQ)
  prefetch_count: 20
  concurrency: 10 processor slots
         │
         ▼
PortalWebhookDeliveryWorker
  1. Record attempt in portal_webhook_deliveries (upsert on delivery_id)
  2. HTTP POST to merchant endpoint (Req, 10s timeout)
  3. Record result (status_code, response_body)
  4. If failed: enqueue Oban WebhookDeliveryRetryWorker
  5. Always ACK the RabbitMQ message (do NOT reject-and-requeue)
```

### Why always-ack (never reject-and-requeue)?

Rejecting a message with requeue (`on_failure: :reject_and_requeue`) in
Broadway causes a tight retry loop: RabbitMQ immediately requeues the message
and Broadway receives it again within milliseconds. This can saturate the
consumer with failing deliveries, starving successful ones.

The correct pattern:
1. Always ACK the RabbitMQ message (removes it from the queue).
2. If delivery failed, schedule a retry via Oban with exponential backoff.
3. Oban publishes a new RabbitMQ message for the retry.

This decouples the retry timing from the consumer loop. Oban's `max_attempts`
and exponential backoff ensure that failing endpoints receive progressively
spaced retries rather than a flood.

### Three deduplication layers

A webhook delivery can be requeued from multiple sources (RabbitMQ retry,
Oban retry, a process crash). Three layers prevent duplicate delivery records:

1. **Core DB:** `outbox_messages.event_id` UNIQUE — each event is relayed once.
2. **Portal DB:** `portal_webhook_deliveries` upsert on `(endpoint_id, event_id, attempt)` — duplicate delivery records for the same attempt are collapsed.
3. **Portal endpoints upsert:** `portal_webhook_endpoints` upsert on `endpoint_id` — duplicate endpoint fan-out is suppressed.

### Dead-letter exchange (DLX) and exhausted retries

After `max_attempts` Oban retries (configurable, default 10), the job is
discarded to the DLX queue: `webhooks.dlx`. The DLX consumer records the final
failed delivery and increments `portal_webhook_endpoints.consecutive_failures`.

When `consecutive_failures >= 50`, the endpoint is auto-disabled:
`disabled_at = NOW()`. The merchant receives a portal notification and an email.
Re-enabling requires explicit merchant action via the portal.

This prevents perpetually failing endpoints from consuming retry budget
indefinitely. Merchants with broken webhook URLs are notified rather than silently
losing delivery.

### Soft-delete for webhook endpoints (ADR-0026)

`portal_webhook_endpoints.deleted_at` is a nullable timestamp (soft delete).
Hard deletion is avoided because `portal_webhook_deliveries` references the
endpoint. A hard delete would orphan delivery records, breaking the audit trail
of "which endpoint received this event".

Soft delete allows the delivery records to remain queryable (`JOIN` still works)
while the endpoint no longer appears in the active endpoint list.

---

## 13. API Key Design and Security

### Key structure

Every merchant API key has the structure:

```
sk_live_<32-byte-random-256-bits>
│─┘│──┘ │─────────────────────────────────┘
│  │    32-byte random (256 bits)
│  mode prefix: live | sandbox | simulation
secret key prefix (sk = secret key)
```

The `key_prefix` column stores the first 12 characters (e.g. `sk_live_<xxx>`).
This allows a merchant to identify which key was used for a request from the
logs, without the logs containing enough bytes to authenticate.

### Hashing and one-way storage

```sql
api_keys
  id          uuid PK
  merchant_id uuid FK
  key_prefix  text     -- first 12 chars of the raw key
  secret_hash text     -- SHA-256(raw key) — irreversible
  label       text     -- human name ("Production Key", "Test Integration")
  mode        yagye_mode
  revoked_at  timestamptz NULL
```

The raw key is returned **exactly once** — in the HTTP response at creation
time. It is never stored in Yagye's database. An attacker who obtains the
`api_keys` table cannot reconstruct the raw keys from the hashes.

Authentication: hash the incoming bearer token and compare against
`secret_hash`. The comparison uses `Plug.Crypto.secure_compare` (constant-time)
to prevent timing attacks.

### Mode binding

Each API key is bound to a mode (`simulation`, `sandbox`, `live`). The `VerifyMode`
plug in the `:v1` pipeline rejects requests where:
- The key's mode is `sandbox` but the merchant makes a `live` resource request.
- The key's mode is `live` but a test endpoint is requested.

Cross-mode access is impossible at the API layer. It is also impossible at the
data layer: every record carries a `mode` column, and queries always filter on mode.

### Key rotation strategy

API keys have no expiry by default. The recommended rotation cadence is 90 days.
Rotation in Yagye:
1. Create a new key (`POST /v1/api-keys`).
2. Update the integration to use the new key.
3. Verify the new key works.
4. Revoke the old key (`DELETE /v1/api-keys/:id`).

Revoking sets `revoked_at = NOW()`. The key continues to appear in audit logs
and the portal's key list (with a "revoked" badge), but authentication rejects
it. Hard deletion is not possible (RESTRICT FK — see §24).

### The `label` column

The `label` column is a free-text name for the key (e.g. "CI integration",
"Mobile app production"). Without labels, a merchant with 3 keys cannot tell
them apart. Labels have no bearing on authentication — they are UX affordances
for operational clarity.

---

## 14. Cursor-Based Pagination

### Why not offset pagination?

Offset pagination (`LIMIT 100 OFFSET 300`) fetches and discards the first 300
rows on every page request. At page 100, PostgreSQL must scan 10,000 rows to
return 100. Cost is O(page_number × page_size) — linear with depth.

For a payments table with millions of rows, deep page queries are prohibitively
expensive. Offset pagination also has a correctness bug: if a new record is
inserted before the offset window, every row in subsequent pages shifts by one.
The client may see a record twice or miss it entirely.

### Keyset (cursor) pagination

Keyset pagination uses a stable anchor — the public ID of the last seen record
— as the cursor. The query becomes:

```sql
-- Forward page (after a given cursor):
SELECT * FROM payments
WHERE merchant_id = $1
  AND id > $cursor    -- UUIDv7: lexicographic sort = chronological sort
ORDER BY id ASC
LIMIT 101;            -- fetch n+1 to determine has_more
```

Cost is O(log N) — the B-tree index on `id` seeks directly to the cursor
position. Page depth has no effect on query time.

### The n+1 fetch for `has_more`

Fetching `n+1` rows to determine whether a next page exists avoids a
`COUNT(*)` query:

```elixir
def paginate(query, limit) do
  rows = query |> limit(limit + 1) |> Repo.all()
  has_more = length(rows) > limit
  {Enum.take(rows, limit), has_more}
end
```

`COUNT(*)` on a large table without a perfect covering index requires a
full sequential scan. The n+1 pattern is always faster.

### `ending_before` (previous page)

To navigate backwards:

```sql
SELECT * FROM payments
WHERE merchant_id = $1
  AND id < $cursor
ORDER BY id DESC
LIMIT 101;
```

The result is in reverse order. The application reverses it in memory before
returning the page. This avoids a `DESC` + reverse-index design, which is
harder to maintain.

### UUIDv7 as a lexicographic sort key

UUIDv7's first 48 bits are a millisecond timestamp. Lexicographic string
comparison of two UUIDv7 values is equivalent to chronological comparison
(for records created in the same millisecond, the random component is used as
a tiebreaker — sufficient for pagination purposes).

The cursor is the public prefixed ID (e.g. `pay_018e…`). Because UUIDv7 IDs
are lexicographically sortable, `id > $cursor` is a valid time-ordered
comparison without parsing the timestamp component.

### Portal pagination: Pagy (page-based)

The portal uses Pagy with mandatory date-range filters instead of cursor
pagination. Human users browsing the portal jump between pages by number, not
by cursor. The date-range filter ensures that no page query scans more than
a bounded time window of data, keeping query cost manageable even with offset
pagination.

---

## 15. Error Envelope and API Conventions

### The Stripe-style error envelope

Every error response from `POST /v1/*` uses the same structure:

```json
{
  "error": {
    "type": "invalid_request_error",
    "code": "amount_too_small",
    "message": "The minimum charge amount is GHS 1.00 (100 pesewas).",
    "param": "amount"
  }
}
```

Fields:
- `type` — broad category: `invalid_request_error | api_error | authentication_error | rate_limit_error`
- `code` — machine-readable constant for the integration to branch on
- `message` — human-readable explanation (for developers, not end users)
- `param` — (optional) the request parameter that caused the error

The envelope is described by the OpenAPI spec and validated in tests. Client
SDKs can pattern-match on `error.code` without parsing `message` strings.

### Why a consistent envelope?

Inconsistent error formats are one of the most common integration friction
points for PSP API users. If some endpoints return `{error: "amount too small"}`
and others return `{message: "invalid amount"}`, client error handling becomes
a fragile chain of `if` statements. A single, documented envelope means a
single error-handling function in the client SDK.

Yagye follows Stripe's design because Stripe's API has been iterated for 15
years and its error taxonomy is battle-tested. We do not invent a new design
when a superior one exists.

### HTTP status codes

```
200 OK           — successful read
201 Created      — successful resource creation
204 No Content   — successful deletion (no body)
400 Bad Request  — malformed request (missing required field, wrong type)
401 Unauthorized — invalid or missing API key
403 Forbidden    — valid key but insufficient permissions
404 Not Found    — resource does not exist or is not visible to this merchant
409 Conflict     — idempotency key reuse with a different request body
422 Unprocessable — semantically invalid request (amount below minimum, etc.)
429 Too Many Requests — rate limit exceeded
500 Internal Server Error — unexpected server error (alert-worthy)
```

`404` is used for both "does not exist" and "exists but belongs to a different
merchant." This is deliberate. Revealing that a resource exists (even via a
`403`) leaks information to an attacker who obtained a partial key.

### OpenAPI-first validation

`OpenApiSpex.CastAndValidate` runs on every `:v1` request before the controller
is called. Invalid requests are rejected at the plug layer — the controller
body never runs. (See §22 for the full OpenAPI discussion.)

---

## 16. Database-Backed RBAC

### Why dynamic, not code-based, roles?

Static role-based access control hardcodes permission checks in application
code. Adding a new permission requires a code deployment. Auditing what a role
can do requires reading code. Creating a custom role for a specific merchant
requires a code change.

Yagye uses DB-backed RBAC: roles, permissions, and their mappings are rows in
the database. Adding a permission or creating a custom role is a data operation,
not a code deployment. The portal UI lets ops administrators manage roles within
the bounds of seeded permissions.

### The four tables

```
roles               permissions
  key text PK         key text PK
  name text           name text
  scope text          description text
  system_role bool    (dotted: 'payments.view',
                        'payments.refund', ...)

role_permissions                user_roles
  role_key FK                     user_id FK
  permission_key FK               role_key FK
  PK: (role_key, permission_key) expires_at timestamptz NULL
                                  revoked_at timestamptz NULL
                                  granted_by_id FK
```

### Seeded roles

Eight roles are seeded at P13 and cannot be deleted via the portal UI
(`system_role = true`):

| Role Key | Scope | Purpose |
|---|---|---|
| merchant_owner | merchant | Full merchant control |
| merchant_finance | merchant | Payments, settlements, exports |
| merchant_developer | merchant | API keys, webhooks, integration |
| merchant_support | merchant | Payments and disputes read-only |
| ops_analyst | internal | Ops read-only across all merchants |
| ops_manager | internal | Ops write (KYB disposition, routing) |
| compliance_analyst | internal | Compliance and screening reads |
| compliance_manager | internal | Compliance decisions |

### The `permitted?` helper

```ruby
class ApplicationPolicy
  def permitted?(key)
    Current.permissions.include?(key)
  end
end
```

`Current.permissions` is populated once per request from the database and
memoized in the request-scoped `Current` object. The first permission check in
a request triggers a single SQL query:

```sql
SELECT p.key FROM permissions p
JOIN role_permissions rp ON rp.permission_key = p.key
JOIN user_roles ur ON ur.role_key = rp.role_key
WHERE ur.user_id = $1
  AND ur.revoked_at IS NULL
  AND (ur.expires_at IS NULL OR ur.expires_at > NOW());
```

All subsequent `permitted?` calls in the same request are O(1) set lookups.

### Time-boxed elevation

`user_roles.expires_at` allows temporary elevation:

```ruby
# Grant ops_manager for 4 hours (break-glass access)
UserRole.create!(
  user_id: ops_user.id,
  role_key: "ops_manager",
  expires_at: 4.hours.from_now,
  granted_by_id: granting_admin.id
)
```

After 4 hours, `permitted?` returns false — the expiry is enforced at query
time, not via a cron job. Expired roles accumulate in the table as an audit
trail of who had what access and when.

### Scope enforcement at the DB layer

The `user_roles` table has a DB CHECK constraint:

```sql
CHECK (
  (scope = 'merchant' AND user_kind = 'merchant') OR
  (scope = 'internal' AND user_kind = 'ops')
)
```

An ops user cannot be assigned a merchant-scope role, and vice versa. This is
enforced at the database level — a buggy Rails callback cannot violate it.

### CI-enforced permission coverage

A CI test asserts that every `permitted?` call in every Pundit policy references
a permission key that exists in the `permissions` table. This prevents a common
footgun: a developer adds a `permitted?("payments.export")` call, but forgets
to seed the `payments.export` permission row. The CI failure surfaces this
immediately rather than at runtime.

---

## 17. Portal as Read Model

### The fundamental design choice

Portal is a **read model** — it consumes events from Core and maintains
projections of Core entities for fast, UI-optimised queries. It is never the
source of truth for financial data.

This is not merely an architectural preference. It is a security boundary:
Portal credentials (Rails database connection string) cannot directly touch
Core's ledger, payment, or settlement tables. Even if the portal were
compromised, the attacker could read portal projections but could not modify
Core's write model.

### What the portal IS authoritative for

```
✓ User sessions and authentication
✓ RBAC roles, permissions, role assignments
✓ Portal notifications (ops alerts, merchant alerts)
✓ Merchant branding settings (logo, colours)
✓ Webhook endpoint configuration
✓ API key metadata (not the raw secret — that is in Core)
✓ Saved filters, UI preferences
✓ Portal-specific audit log (who logged in, what they exported)
```

### What the portal IS NOT authoritative for

```
✗ Ledger balances (read from Core's proj_merchant_balances)
✗ Payment state (portal_payments is a projection — may be 1-2s behind)
✗ Settlement amounts (read from Core)
✗ Fee calculations (Core's pricing engine is the source)
✗ Dispute adjudication results (Core owns disputes)
✗ Merchant KYB status (Core owns merchant records)
```

When in doubt: if money is involved, the authoritative source is Core.

### The projection pipeline

```
Core DB: outbox_messages
         │ (published_at IS NULL)
         │ OutboxRelayWorker polls every ~1s
         ▼
Oban: PaymentProjectionWorker
         │ SQL upsert with version fencing
         ▼
Portal DB: portal_payments
         │ Solid Cable broadcast
         ▼
Browser: Turbo Stream live update (no page reload)
```

At P14, the Oban relay is replaced by Redpanda. The projection worker becomes
a Karafka consumer. The idempotency strategies (§7) remain unchanged — the
projection logic is broker-agnostic.

### "Rebuilt, not versioned"

Portal projection tables (e.g. `portal_payments`) do not use `has_paper_trail`
(versioning library) and do not use soft delete. The reasoning:

> "Rebuilt, not versioned."

If a portal projection row is corrupted or incorrect, it can be rebuilt by
replaying the Core events from the outbox. Versioning or soft-deleting a row
that will be rebuilt anyway adds overhead without benefit.

This is distinct from Core's RESTRICT FK policy. Core records must not be
deleted because they are the source of truth. Portal records can be deleted
and rebuilt because they are projections.

---

## 18. Settlement and Reconciliation

### What settlement is

Settlement is the process of moving accumulated merchant payables from Yagye's
ledger into the merchant's bank account. It has four phases:

1. **Sweep** — identify all eligible `merchant_payable` postings for the settlement
   period (daily by default), compute net amounts (gross minus platform fees).
2. **Batch creation** — create a `settlement_batch` record with `net_amount` locked.
3. **Approval** — an ops manager approves the batch (SoD: approver ≠ creator).
4. **Dispatch** — the `BankDispatchWorker` initiates the bank wire transfer.

### The `net_amount` lock

`settlement_batches.net_amount` is set once, at batch creation time, and is
thereafter immutable. The `BankDispatchWorker` reads this locked amount for
the bank wire. This prevents a race condition where fee changes between batch
creation and dispatch alter the amount sent to the merchant's bank.

```sql
settlement_batches
  gross_amount    bigint   -- sum of eligible postings
  platform_fees   bigint   -- sum of fee_payable postings for the period
  net_amount      bigint   -- gross - platform_fees, immutable after set
  dispatch_approved_by uuid
  dispatch_approved_at timestamptz
```

### SoD in settlement

The settlement approval chain enforces SoD at the database level:

```sql
CHECK (
  dispatch_approved_by IS NULL
  OR dispatch_approved_by IS DISTINCT FROM created_by
)
CHECK (
  dispatch_rejected_by IS NULL
  OR dispatch_rejected_by IS DISTINCT FROM created_by
)
```

The person who creates the settlement batch cannot approve it. This is enforced
by the DB constraint, not just the Rails UI — a developer running raw SQL cannot
bypass it without disabling the constraint.

### Reconciliation

Reconciliation runs after settlement to verify that what was sent to the bank
matches what the ledger records. It also resolves `resolution_pending` payment
attempts (§10):

```
ReconciliationWorker (daily):
  For each resolution_pending payment attempt:
    1. Query provider API with idempotency_token
    2. Provider confirms: succeeded | failed | not_found
    3. Update payment_attempt state
    4. If succeeded: trigger ledger entries
    5. If failed / not_found: mark abandoned after window
```

Reconciliation closes the loop on indeterminate provider responses. Without it,
a payment where the provider confirmed success but the callback was lost would
remain in `resolution_pending` indefinitely.

### The `adjustment_approvals` SoD

Manual ledger adjustments (corrections to posting errors, dispute credits) flow
through `adjustment_approvals`:

```sql
adjustment_approvals
  proposed_by  uuid FK  -- who proposed the adjustment
  approved_by  uuid FK  -- who approved (must differ from proposed_by)
  rejected_by  uuid FK

CHECK (approved_by IS NULL OR approved_by != proposed_by)
CHECK (rejected_by IS NULL OR proposed_by IS DISTINCT FROM rejected_by)
```

Note: `adjustment_approvals` is Core-owned, not portal-owned. The SoD
constraint is enforced in the database where the write actually occurs.
An ops UI that submits adjustments via the portal calls Core's
`/internal/adjustment-approvals` endpoint. The constraint fires in Core's
PostgreSQL — not in Portal's database, which is a read model.

---

## 19. The Pricing Engine

### Why a configurable pricing engine?

Different merchants have different commercial agreements. A high-volume merchant
may negotiate a lower fee rate. An enterprise merchant may have a hybrid model:
fixed fee per transaction plus a percentage. Promotional periods may apply
reduced rates.

Hardcoding fees in application logic requires a code deployment every time a
merchant's pricing changes. A DB-backed pricing engine allows the ops team to
configure pricing via the portal without code changes.

### `pricing_plans` and `pricing_rules`

```
pricing_plans
  id              uuid PK
  merchant_id     uuid NULL  (NULL = platform default)
  status          text       draft | active | archived
  fee_mode        text       deducted | invoiced
  created_by      uuid FK
  activated_by    uuid FK
  CHECK (activated_by IS NULL OR created_by IS DISTINCT FROM activated_by)

pricing_rules
  id                uuid PK
  plan_id           uuid FK
  payment_method    text NULL
  currency          text NULL
  network_code      text NULL
  percentage_bps    integer   (basis points: 150 = 1.50%)
  fixed_amount      bigint    (minor units)
  specificity       integer   (precomputed: count of non-null filters)
  approved_by       uuid FK
  CHECK (approved_by IS DISTINCT FROM created_by)
  deleted_at        timestamptz NULL  (soft-delete for historical fee computation)
```

### SoD in pricing

Two SoD constraints:

1. `pricing_plans`: The person who creates a plan cannot activate it.
   (`activated_by IS DISTINCT FROM created_by`)
2. `pricing_rules`: The person who creates a rule cannot approve it.
   (`approved_by IS DISTINCT FROM created_by`)

These prevent a single actor from unilaterally lowering fees for a merchant
(a fraud vector at payment companies). Four eyes must review any pricing change.

### Fee resolution at dispatch time

The pricing engine selects the most specific applicable rule at dispatch time:

```elixir
def resolve_fee(payment, merchant_id) do
  plan = active_plan_for(merchant_id) || platform_default_plan()

  plan.pricing_rules
  |> filter_applicable(payment)  # currency, method, network match
  |> sort_by_specificity_desc()
  |> List.first()
  |> compute_fee(payment.amount)
end
```

The `specificity` column is precomputed at rule creation: a rule matching all
three of `currency + method + network_code` has specificity 3; a rule matching
only `currency` has specificity 1. Most-specific wins.

### Fee lock at dispatch

The fee amount is computed and locked at dispatch time, not at settlement time.
This means:

- If a merchant's pricing plan changes after a payment is dispatched, the fee
  for the already-dispatched payment is not retroactively changed.
- `payment_attempts.fee_amount` stores the locked fee.
- Settlement sweeps sum the locked `fee_amount` values, not the current plan.

### `deleted_at` on `pricing_rules`

Pricing rules use soft delete (`deleted_at`) instead of hard delete. This is
necessary for historical fee computation: to answer "what fee applied to this
payment from 3 months ago?", the fee engine must be able to query the rule
that was active at that time, even if it has since been superseded.

Soft-deleting the rule preserves it for historical queries while excluding it
from the active rule set (`WHERE deleted_at IS NULL`).

---

## 20. Structured Logging and Observability

### Structured JSON: why text logs are not enough

Free-text log messages are read by humans. Structured JSON logs are read by
both humans and machines. The difference matters at scale:

- **Query time.** To find all payments above GHS 1000 from a specific merchant
  that took more than 5 seconds, a text log requires a regex. A JSON log
  requires a filter: `merchant_id = X AND amount > 100000 AND duration_ms > 5000`.

- **Correlation.** A `trace_id` field links every log line from a single
  request — API call, provider dispatch, webhook delivery, projection update —
  across multiple services.

- **Alerting.** Loki alerting rules operate on field values, not text patterns.

### What every log line contains

```json
{
  "time":          "2026-10-18T12:00:00.123Z",
  "level":         "info",
  "message":       "payment dispatched",
  "trace_id":      "00-4bf92f3577b34da6-00f067aa0ba902b7-01",
  "merchant_id":   "mch_018e...",
  "payment_id":    "pay_018e...",
  "provider_code": "mtn_momo_gh",
  "mode":          "live",
  "duration_ms":   142
}
```

### What is never logged

| Never log | Reason |
|---|---|
| `user_email` | PII — regulatory risk |
| Raw MSISDN | PII — mobile number is sensitive |
| Full API key | Would allow authentication from logs |
| Full request body | May contain card numbers or credentials |
| `password` / `secret` fields | Obvious |

If a developer adds a `Logger.info("user: #{user.email}")` line, CI's secret
scanning and code review should catch it. The no-email-in-logs rule is in
`MEMORY.md` specifically because it has been raised as a non-obvious constraint.

### Trace propagation

Every inbound request generates a `trace_id` in W3C `traceparent` format. This
ID is:

1. Stored in `api_requests.trace_id` — queryable in PostgreSQL.
2. Added to Logger metadata for all log lines in that request.
3. Forwarded in outgoing provider HTTP calls (`X-Request-ID` header).
4. Included in `outbox_messages.envelope` so downstream workers log the
   originating trace context.
5. Propagated to Oban job arguments.

A single `trace_id` query in Loki reconstructs the full story of any
transaction — the API call, the provider dispatch, the provider callback, the
ledger entries, the projection update, and the webhook delivery.

### The observability stack

```
Core / Portal / Simulator
  │  structured JSON logs
  │  OpenTelemetry spans (OTLP)
  ▼
Grafana Alloy  (agent, on each host)
  ├─ ships logs ──────────────► Loki  (log aggregation)
  ├─ ships traces ────────────► Tempo (distributed tracing)
  └─ scrapes metrics ─────────► Prometheus-compatible Metrics
                                    │
                                    ▼
                              Grafana dashboards
                              (single pane of glass)
```

OTLP is disabled in `dev.exs` — human-readable format is used locally.
In staging and production, compact JSON is sent to Loki. The switch is a
single `logger_formatter` config change, not a code change.

### Alerting philosophy

Alerts fire on conditions that require human action, not on conditions that
resolve automatically. The distinction:

- **Alert:** `outbox_messages` has rows with `publish_attempts > 5` (relay is
  stuck — human must investigate).
- **No alert:** A single payment dispatches with `duration_ms > 3000` (transient
  provider latency — system retries automatically).

Alert fatigue is a real operational problem. Over-alerting trains operators
to ignore alerts. Yagye's alerting ruleset is reviewed quarterly.

---

## 21. Concurrency and the BEAM

### Why the BEAM matters for a PSP

The BEAM (Erlang Virtual Machine, which Elixir runs on) was designed for
telecom switches: systems that must handle millions of concurrent connections,
tolerate process failures without system-wide restarts, and never stop.

A PSP has similar requirements:
- Thousands of concurrent payment dispatches (each with a blocking HTTP call
  to a provider).
- Background jobs that must not block payment processing.
- Provider callbacks that arrive asynchronously.
- A relay worker polling the outbox every second.

The BEAM's concurrency model handles all of this without threads, locks, or
shared mutable state.

### Per-process isolation

Each BEAM process is fully isolated: it has its own heap, its own mailbox, and
its own garbage collector. A crash in one process does not affect others.
The supervision tree restart policy determines what happens after a crash.

For a PSP, this means:
- A crashing payment dispatch process does not kill the relay worker.
- A memory leak in a webhook delivery does not affect the main API process.
- The Oban job that processes a bad message fails gracefully — the other jobs
  in the queue continue.

### Preemptive scheduling

The BEAM scheduler is preemptive — no single process can monopolise a CPU
core. Processes are scheduled in "reductions" (roughly, function call counts).
A process that runs for too long is preempted and put back in the queue.

This means a slow provider HTTP call (e.g. MTN MoMo taking 10 seconds to
respond) does not block other API requests. The HTTP call runs in a separate
process or uses `Req`'s async mode. The API endpoint process handles other
requests while waiting.

### Oban: PostgreSQL-backed job queuing

Oban stores jobs in PostgreSQL, not in memory or Redis. This gives:
- **Durability:** A BEAM node restart does not lose queued jobs.
- **Observability:** Jobs are rows in the `oban_jobs` table — queryable with
  `SELECT * FROM oban_jobs WHERE state = 'retryable'`.
- **Correctness:** Advisory locks prevent two Oban nodes from picking up the
  same job concurrently (no duplicate execution from the queue layer).

Oban queues used in Yagye Core:

| Queue | Purpose | Concurrency |
|---|---|---|
| `default` | General-purpose workers | 10 |
| `outbox` | OutboxRelayWorker (high priority) | 1 |
| `dispatch` | PaymentDispatchWorker | 20 |
| `webhooks` | WebhookFanoutWorker | 5 |
| `reconciliation` | Daily reconciliation workers | 2 |

Queue concurrency is tuned to match the external API rate limits — no point
having 100 concurrent dispatch workers if MTN MoMo's API allows 10 req/s.

### `Req` for provider HTTP

Yagye uses `Req` (the Elixir HTTP client library) for all provider API calls.
`Req` is non-blocking: the calling process yields while the TCP connection is
established and the response is received. This is distinct from a blocking
`HTTPoison` call that would hold a process and its reductions until a response
arrives.

`Req.Test` stubs HTTP responses at the test layer, allowing unit tests of
provider adapters without a real HTTP server. The gateway_simulator provides
real HTTP responses for integration testing. (ADR-0028 documents this strategy.)

---

## 22. OpenAPI-First Design

### What "OpenAPI-first" means

In a traditional "code-first" approach, the API is implemented, then documented.
The documentation lags the implementation. Edge cases and undocumented fields
accumulate. Clients rely on undocumented behaviour.

"OpenAPI-first" inverts this: the OpenAPI spec is the contract. Code that
deviates from the spec is a bug. The spec is the single source of truth for:
- Request schema validation
- Response schema validation
- Error format documentation
- SDK generation

### `OpenApiSpex.CastAndValidate`

In the `:v1` pipeline:

```elixir
plug OpenApiSpex.Plug.CastAndValidate,
  json_render_error_v2: true,
  replace_params: true
```

This plug:
1. Parses the OpenAPI spec (loaded at startup from the spec module).
2. Validates the incoming request against the operation's request schema.
3. Casts query parameters and body fields to their declared types.
4. Returns a `422` with a structured error if validation fails.

The controller never sees an invalid request. The `conn.body_params` in the
controller are already cast to the correct types — `amount` is an integer,
not a string.

### The spec is served at `GET /api/openapi`

```
GET /api/openapi
Content-Type: application/json

→ Returns the full OpenAPI 3.1 spec as JSON
```

No auth required. This endpoint is what the portal's API documentation page
and merchant-facing SDK documentation generators consume.

### Contract testing

A CI test suite (`test/openapi_test.exs`) sends requests to every documented
endpoint and asserts that the responses conform to the documented response
schemas. This prevents the spec from drifting from the implementation silently.

### Versioning policy

The `:v1` prefix is the API version. Breaking changes require a new `/v2`
prefix. The `api_version` field on the `Merchant` object (not a request header)
signals to Core which response format the merchant's integration expects.

Non-breaking additions (new optional fields) are added to v1 without a version
bump. Removals and type changes always require a new version.

---

## 23. Mode Isolation

### Why mode is a column, not a config flag

Yagye operates in three modes: `simulation`, `sandbox`, `live`. If mode were
an environment variable, a `sandbox` API key could potentially query live
records in the same database — there is no data-layer enforcement.

With `mode` as a column on every record:

1. `VerifyMode` plug rejects cross-mode requests at the API layer.
2. All Core query objects filter on mode automatically.
3. Auditors can query `WHERE mode = 'live'` trivially.
4. Settlement and reporting never accidentally include simulation traffic.

Cross-mode contamination has caused real financial losses at payment companies.
The column-per-row design eliminates this class of bug by making it structurally
impossible — not just documented as a prohibited practice.

### How simulation works end-to-end

```
Merchant sends: POST /v1/payments  with a simulation API key
                      │
Core VerifyMode:  key.mode = 'simulation' ✓
                      │
Core writes:      payments.mode = 'simulation'
                  ledger_postings.mode = 'simulation'
                      │
Routing:          All simulation payments route to gateway_simulator
                  (ProviderCredential for simulation points to simulator URL)
                      │
gateway_simulator: Returns deterministic outcome based on MSISDN prefix
                   024 100 0001 → success
                   024 100 0002 → insufficient_funds
                   024 100 0003 → timeout
                      │
Core callback:    Updates payment state. Writes ledger entries.
                  All with mode = 'simulation'.
                      │
Outbox relay:     Publishes portal projection event.
                  Event carries mode = 'simulation'.
                      │
Portal:           Projects into portal_payments with mode = 'simulation'.
                  Visible only to simulation-mode portal views.
```

The gateway_simulator is stateless. It speaks the same HTTP protocol as real
providers so Core's provider adapters are tested against real HTTP without
sandbox credentials. (ADR-0013)

### Mode propagation to downstream records

Every record created as a consequence of a simulation payment inherits the
`simulation` mode:
- The `payment` record
- All `ledger_entries` and `ledger_postings`
- All `outbox_messages`
- The `portal_payments` projection
- Any `settlement_batches` (simulation settlement is a no-op for real bank wires)

A simulation payment can never trigger a real bank wire because the
`BankDispatchWorker` checks `WHERE mode = 'live'` before dispatching.

---

## 24. No Hard Deletes and Audit Trails

### The regulatory requirement

PSP regulations (and general financial regulation) require that financial
records be retained for 7 years. A hard delete permanently destroys a record.
If a Ghanaian regulator requests the history of a specific payment, Yagye must
be able to produce it.

### RESTRICT FK: the structural enforcement

Every domain FK is `ON DELETE RESTRICT`:

```sql
ALTER TABLE payment_attempts
  ADD CONSTRAINT fk_payment_id
  REFERENCES payments(id) ON DELETE RESTRICT;
```

Attempting to delete a `payment` that has `payment_attempts` rows fails at the
database level with:

```
ERROR: update or delete on table "payments" violates foreign key constraint
```

This is enforced by the database, not application code. A runaway migration, a
developer executing raw SQL, or a bug in a context function cannot delete a
payment that has downstream references.

The RESTRICT constraint makes it structurally difficult to violate the 7-year
retention requirement — you would need to delete all downstream records first,
which is itself impossible if those records have their own RESTRICT-FK references.

### What happens instead of deletion

| Instead of | We do |
|---|---|
| Delete an API key | Set `revoked_at = NOW()` |
| Delete a merchant | Set `deactivated_at = NOW()` |
| Remove a pricing rule | Set `deleted_at = NOW()` (soft delete) |
| Cancel a settlement | Write a reversing entry to the ledger |
| Void a payment | Create a `payment_attempt` with `type = 'void'` |

The record remains in the database and participates in audit queries. The
"active" query scope simply adds `WHERE revoked_at IS NULL` or
`WHERE deleted_at IS NULL`.

### Portal soft delete vs Core RESTRICT FK

Portal and Core have different deletion policies (ADR-0026):

**Core:** RESTRICT FK everywhere. Financial records are source-of-truth and
must never be destroyed.

**Portal:** Soft delete (`deleted_at`) for portal-managed records that have
JOIN dependencies. Example: `portal_webhook_endpoints` uses soft delete because
`portal_webhook_deliveries` references the endpoint. A hard delete would orphan
delivery records and break the audit trail. But the endpoint is not a Core
financial record — it is a portal configuration record. Soft delete is correct.

### The audit log

`portal_audit_events` records every significant action taken via the portal:

```
portal_audit_events
  actor_id       uuid FK → users
  actor_ip       inet
  event_type     text   ("webhook_endpoint.created", "api_key.revoked", ...)
  resource_type  text
  resource_id    uuid
  metadata       jsonb
  created_at     timestamptz
```

This table is append-only (RESTRICT FK, no soft delete, no hard delete). It is
the portal's own source of truth for "who did what and when."

---

## 25. Agentic API Surface

### The emerging reality of AI-driven integrations

A growing class of Yagye's merchant integrations will be built using LLM-powered
agents — tool-use loops where a model calls `POST /v1/payments`, processes the
result, and decides whether to retry. This is already happening with Claude,
GPT-4o, and similar models embedded in merchant backends.

Agentic integrations introduce failure modes that human-driven integrations
do not have:

1. **Hallucinated failures.** A model may "decide" that a payment failed and
   retry it — even if the API returned `201 Created`. The idempotency key
   prevents a duplicate charge, but only if the agent sends the same key on
   retry.

2. **Unbounded retry loops.** A buggy agent may call `POST /v1/payments` in a
   tight loop without exponential backoff. Rate limiting prevents runaway charges,
   but the agent may still exhaust its token budget on retries.

3. **Parameter drift across retries.** An agent may change the `amount` field
   between retries (e.g. recalculating from a different context). The idempotency
   key's request fingerprint check catches this and returns a `400`.

4. **Opaque tool descriptions.** If the API documentation is not LLM-readable,
   models generate incorrect tool calls. OpenAPI specs are machine-readable —
   client SDKs derived from the spec provide correctly-typed tool definitions.

### Design choices that protect agentic integrations

**Idempotency key enforcement (§4):** The idempotency state machine is the
primary protection. An agent MUST pass a stable idempotency key for every
payment. The key should be derived from the business intent (e.g. the order ID),
not from a timestamp or random value.

```python
# Correct: stable key derived from order
client.payments.create(
    amount=5000,
    currency="GHS",
    idempotency_key=f"order-{order_id}"
)

# Wrong: random key on each call — no duplicate protection
client.payments.create(
    amount=5000,
    idempotency_key=str(uuid4())  # new UUID every call!
)
```

**Descriptive error codes (§15):** Agents branch on `error.code`, not
`error.message`. A code like `amount_too_small` with clear documentation allows
an agent to self-correct (adjust the amount) rather than hallucinating a retry.

**Rate limiting (§11 velocity + HTTP 429):** Velocity limits at the account
level prevent a looping agent from creating unbounded charges. The `429`
response includes `Retry-After` — a well-behaved agent SDK will honour it.

**OpenAPI spec availability (§22):** The spec at `GET /api/openapi` is consumed
by SDK generators and by the LLM tool definition generator. A model with a
correctly-typed tool definition is less likely to send malformed requests.

**Structured logging for agent observability:** Every API call logs
`trace_id`, `merchant_id`, `idempotency_key` (masked), and `duration_ms`.
Merchants debugging an agent integration can query Loki for all calls from
a specific idempotency key prefix and reconstruct the agent's call sequence.

### The idempotency key as a session correlator

Beyond duplicate protection, the idempotency key serves as a session correlator
for agentic integrations. An agent processing an e-commerce order may make
multiple API calls (create payment, verify status, issue refund). Using a
consistent key prefix (e.g. `order-{order_id}-*`) allows a merchant to query
all API calls related to a specific order:

```sql
SELECT * FROM api_requests
WHERE idempotency_key_prefix LIKE 'order-12345-%'
ORDER BY created_at ASC;
```

This is especially valuable for debugging agent loops where it is not clear
which call succeeded and which was a duplicate.

### ADR-0024: Agentic API considerations

ADR-0024 documents the formal design constraints for agentic compatibility:
- All mutating endpoints require an `Idempotency-Key` header.
- Error envelopes use machine-readable codes, not free-text messages.
- Response schemas are fully documented in the OpenAPI spec.
- The spec is available without authentication.
- Rate limit responses include `Retry-After`.
- The idempotency state returns `409 Conflict` (not a `4xx` that an agent
  might interpret as "try again with new parameters").

---

## 26. Oban Workers, Retry Logic, and Provider Failure Scenarios

### Oban: PostgreSQL as the job queue

Every background job in Yagye Core is an Oban worker. Oban stores jobs as rows
in the `oban_jobs` PostgreSQL table. The defining property: **inserting a job and
performing the triggering state change happen in the same database transaction**.

```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:payment, Payment.create_changeset(attrs))
|> Ecto.Multi.insert(:outbox, OutboxMessage.build(...))
|> Oban.insert(:dispatch_job, PaymentDispatchWorker.new(%{payment_id: id}))
|> Repo.transaction()
```

If the transaction rolls back — for any reason — the job row does not exist.
No orphaned job will try to dispatch a payment that was never created.
If the node crashes after the commit, the job row is still in the database
and any live node will pick it up.

### Worker structure: the DDD folder rule

```
lib/yagye_core/payments/workers/
  payment_dispatch_worker.ex
  payment_reconciliation_worker.ex
  webhook_fanout_worker.ex

lib/yagye_core/outbox/workers/
  outbox_relay_worker.ex

lib/yagye_core/settlements/workers/
  settlement_sweep_worker.ex
  bank_dispatch_worker.ex
  reconciliation_worker.ex
```

Every worker lives in the `workers/` subdirectory of its domain context.
The module name mirrors the file path. Workers only call their domain's context
functions — never a sibling context directly.

### Queue configuration and concurrency tuning

```elixir
# config/config.exs
config :yagye_core, Oban,
  queues: [
    default:        10,   # general-purpose
    outbox:          1,   # OutboxRelayWorker — single serial relay
    dispatch:       20,   # PaymentDispatchWorker — concurrency bounded by provider rate limits
    webhooks:        5,   # WebhookFanoutWorker
    reconciliation:  2,   # daily reconciliation — deliberate throttle
    settlement:      1    # SettlementSweepWorker — serial to prevent double-sweeps
  ]
```

The `outbox` queue runs with concurrency 1 — not because it can't be parallelised,
but because the relay reads `ORDER BY id ASC LIMIT 100` and marking `published_at`
must happen before the next poll picks up the same rows. A single relay instance
guarantees sequential relay order without locking complexity.

The `dispatch` queue has concurrency 20 because each job makes a blocking
HTTP call to a provider. With concurrency 20, up to 20 provider calls can be
in-flight simultaneously. The BEAM scheduler handles the concurrent blocking calls
efficiently via preemptive scheduling (§21).

### Retry policy and exponential backoff

Every Oban worker declares its retry behaviour:

```elixir
defmodule YagyeCore.Payments.Workers.PaymentDispatchWorker do
  use Oban.Worker,
    queue: :dispatch,
    max_attempts: 5,
    priority: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => id}, attempt: attempt}) do
    # attempt is 1-indexed: 1, 2, 3, 4, 5
    payment = Payments.get_payment!(id)
    ...
  end
end
```

Oban's default backoff formula: `attempt^4 + 15` seconds.

| Attempt | Delay before retry |
|---|---|
| 1 (initial) | — (runs immediately) |
| 2 | 16 seconds (1^4 + 15) |
| 3 | 31 seconds (2^4 + 15) |
| 4 | 96 seconds (3^4 + 15) |
| 5 | 271 seconds (4^4 + 15) |
| Max reached | Job moves to `discarded` state |

Custom backoff for time-sensitive workers:

```elixir
@impl Oban.Worker
def backoff(%Oban.Job{attempt: attempt}) do
  # webhook delivery: slower backoff to respect merchant server recovery time
  trunc(:math.pow(2, attempt) * 60)  # 2min, 4min, 8min, 16min, 32min
end
```

### The MTN-down scenario: endless pending and how we break it

This is the most operationally important failure mode in a West African PSP.

**The scenario:**

1. Customer initiates a GHS 200 MoMo payment.
2. Core dispatches to MTN MoMo via HTTP POST `/v1_0/requesttopay`.
3. MTN MoMo's API accepts the request (HTTP 202) and sends the USSD prompt.
4. MTN's network experiences an outage (common: 2AM system maintenance,
   network congestion, database issues on their side).
5. The customer approves the USSD prompt but the confirmation never reaches MTN's
   server — or MTN's server processes it but the webhook call back to Yagye fails.
6. Core's `PaymentDispatchWorker` has a running HTTP request that times out
   after 30 seconds.

**What happens without proper handling:**

```
payment_attempt.state = 'dispatched'  ← stuck forever
payment.state = 'processing'          ← stuck forever
Merchant's dashboard: "payment pending"
Customer's UX: nothing, confused
```

The merchant cannot issue a refund (payment not succeeded). The customer's
money may or may not have been deducted. Nobody knows.

**How Yagye handles it — the full resolution chain:**

```
STEP 1: Timeout detected (HTTP client timeout, 30s)
  PaymentDispatchWorker catches {:error, :timeout}
  error_class = 'indeterminate'  ← we don't know if charge applied
  payment_attempt.state = 'resolution_pending'
  payment.state = 'processing'
  Oban job: schedule ReconciliationWorker for +15 minutes

STEP 2: ReconciliationWorker runs (15 min later)
  Query MTN MoMo API: GET /v1_0/requesttopay/{idempotency_token}
  The idempotency_token (stored on payment_attempts) is OUR token,
  sent to MTN with the original charge request.
  MTN can look it up and tell us the final status.

  Response possibilities:
    A. status: "SUCCESSFUL"   → charge applied → trigger ledger + succeeded
    B. status: "FAILED"       → charge not applied → mark failed, safe to retry
    C. 404 Not Found          → MTN never received it → mark timed_out, safe to retry
    D. 503 / timeout          → MTN still down → reschedule for +30 min

STEP 3A: If MTN confirms SUCCESSFUL
  Ecto.Multi:
    UPDATE payment_attempts SET state = 'succeeded'
    UPDATE payments SET state = 'succeeded'
    INSERT ledger_entries (with effective_at = original dispatch time, not now)
    INSERT ledger_postings (DR suspense, CR float, DR float, CR merchant_payable)
    INSERT outbox_messages (payment.succeeded)
  → Merchant receives payment.succeeded webhook (late delivery)
  → Customer's UX eventually shows success

STEP 3B: If MTN confirms FAILED or 404
  UPDATE payment_attempts SET state = 'timed_out'
  UPDATE payments SET state = 'failed'
  → Merchant receives payment.failed webhook
  → Customer was never charged (safe to retry with new payment)

STEP 3D: MTN still unresponsive
  ReconciliationWorker reschedules with backoff:
    +30 min, +2 hours, +8 hours, +24 hours
  After 7-day reconciliation window:
    payment_attempt.state = 'abandoned'
    payment.state = 'abandoned'
    ops alert: "Payment requires manual review"
    Manual ops action: contact MTN directly, query their records
```

**Why the idempotency_token is essential:**

```elixir
payment_attempts
  idempotency_token text
  -- "OUR token, sent to THEM, so a charge is findable after a timeout"
```

Without this token, there is no way to query MTN's systems for the outcome
of a specific charge. We would only know the customer's MSISDN and amount —
insufficient to uniquely identify the transaction (the same customer may have
made multiple payments that day).

The token is a UUID generated by Core before the HTTP request and sent as:
- MTN MoMo: `X-Reference-Id` header
- Stripe: `Idempotency-Key` header
- Flutterwave: `tx_ref` body field

Each provider has a different field name. The adapter translates.

**Circuit breaker protection:**

After 5 consecutive `resolution_pending` outcomes from the same provider,
Core's circuit breaker opens:

```
ProviderHealthTracker.check("mtn_momo_gh")
  consecutive_failures >= 5:
    → circuit_breaker_state = 'open'
    → routing engine: no valid rule found for MTN MSISDN
    → payment fails fast with error: 'provider_circuit_open'
    → alert ops: "MTN MoMo circuit open"

After 5 minutes: half-open (probe one request through)
  success → closed
  failure → open again with extended timeout
```

The routing engine checks `circuit_breaker_state` before selecting a provider.
An open circuit means no valid rule exists for that network — the payment fails
fast rather than dispatching to a known-down provider. **There is no fallback
to another network** (Vodafone cannot charge an MTN MSISDN). The merchant's
customer sees a clear error and can retry later or use a different payment method
(e.g. card if enabled). Ops receive a Grafana alert to engage MTN support.

### Webhook delivery worker chain

The webhook delivery involves two Oban workers chained together:

```
WORKER 1: WebhookFanoutWorker
  Triggered by: OutboxRelayWorker relaying 'payment.succeeded' from outbox
  Queue: webhooks (concurrency: 5)
  Work: Find all active endpoint subscriptions for this merchant+event_type
        For each endpoint:
          Publish to RabbitMQ exchange "webhooks.delivery"
  max_attempts: 3 (fan-out is not delivery — just enqueuing to RabbitMQ)

  ↓ RabbitMQ per-merchant queue

BROADWAY CONSUMER: PortalWebhookDeliveryConsumer
  Picks up from RabbitMQ
  Executes HTTP POST to merchant endpoint
  Records attempt in portal_webhook_deliveries
  ALWAYS ACKs RabbitMQ message
  If HTTP failed: Oban.insert(WebhookDeliveryRetryWorker, ...)

  ↓

WORKER 2: WebhookDeliveryRetryWorker  (lives in portal, not core)
  Queue: webhook_retries (concurrency: 10)
  max_attempts: 10
  Custom backoff:
    attempt 1: 5 min
    attempt 2: 30 min
    attempt 3: 2 hours
    attempt 4: 8 hours
    attempt 5: 24 hours
    attempt 6-10: 3 days each
  On max_attempts:
    → portal_webhook_endpoints.consecutive_failures++
    → if >= 50: disabled_at = NOW()
    → DLX queue consumer records final failure
    → Ops alert + merchant email notification
```

### Oban testing protocol

In tests, Oban runs in `testing: :inline` mode for unit tests (workers execute
synchronously within the test) or `testing: :manual` mode for integration tests
(workers must be explicitly drained):

```elixir
# Unit test: worker executes immediately
use Oban.Testing, repo: YagyeCore.Repo

test "payment dispatch enqueues correctly" do
  perform_job(PaymentDispatchWorker, %{"payment_id" => id})
  assert_enqueued worker: OutboxRelayWorker  # side-effect job enqueued
end

# Integration test: drain specific queue
Oban.drain_queue(queue: :dispatch)
assert payment.state == "succeeded"
```

No test bypasses Oban with `Process.send` or raw function calls to worker
`perform/1`. The `Oban.Testing` helpers are the canonical testing interface.

### Dead-letter and discarded job handling

When a job exceeds `max_attempts`, Oban moves it to `state: 'discarded'`. The
job row remains in `oban_jobs` — never deleted. The `oban_jobs` table has
`Oban.Plugins.Pruner` configured to remove completed/cancelled jobs after 7 days
but retain discarded jobs for 30 days for ops inspection.

An ops Grafana alert fires when `SELECT COUNT(*) FROM oban_jobs WHERE state = 'discarded'`
exceeds a threshold. Discarded payment dispatch jobs require manual review — they
represent payments where all automatic resolution attempts have been exhausted.

---

## 27. Architecture Pattern — What Kind of System Is Yagye?

Before discussing individual components, it helps to name the overall
architectural pattern. Yagye is a **hybrid event-driven system** — not a
pure event-driven architecture, not a traditional request-response monolith,
and deliberately not event sourcing or CQRS.

### Request-response at the API boundary

Every payment, refund, and merchant operation enters through a synchronous
HTTP API. The caller sends a request and waits for a response. This is
intentional: merchants need a synchronous confirmation (or rejection) at the
point of creating a payment. The alternative — an async API where the caller
polls for the result — creates integration complexity for merchant developers
and is not how any mainstream PSP API works.

### Event-driven internally

After the HTTP boundary, Yagye is event-driven:

1. A state change in Core (e.g. `payment_attempt.succeeded`) writes an event
   to the `outbox_events` table in the **same transaction** as the state change.
2. The `OutboxRelayWorker` picks up the event and publishes it to Redpanda.
3. Portal's Karafka consumers receive the event and update Portal's read model.
4. The same event is also fanned out to merchant webhook endpoints via RabbitMQ.

This internal event flow means Core and Portal are **decoupled by events**:
Portal does not query Core's database. Portal does not call Core's internal
functions. Portal knows only what events Core has published.

```
HTTP request → Core (synchronous, ACID)
                 │
                 └── outbox_events (same transaction)
                          │
                     OutboxRelayWorker
                          │
                     Redpanda topic
                    ╱             ╲
             Portal              Data
             (Karafka)           Platform
             read model          (Bronze)
```

### Not event sourcing

Event sourcing means the **event log is the source of truth**. State is
reconstructed by replaying events. There is no "current state" row — only
an immutable sequence of events.

Yagye does **not** use event sourcing. The source of truth is the state
table. `payments.status` is the authoritative record of a payment's current
state. Events in the outbox are notifications of state changes — they carry
the new state, but they are derived from the state table, not the other way
around.

The distinction matters:

| | Event Sourcing | Yagye |
|---|---|---|
| Source of truth | Event log | State table (PostgreSQL) |
| Current state | Reconstructed by replaying events | Read directly from the row |
| Event role | Authoritative (entities ARE their events) | Notification (events reflect row changes) |
| Point-in-time query | Replay up to timestamp | Need SCD Type 2 or audit log |
| Operational complexity | High (projection rebuilds, snapshot management) | Low (standard SQL) |

### Not CQRS

Command Query Responsibility Segregation (CQRS) means the write model and
the read model are separate systems with separate schemas. Commands go to
the write store; queries go to the read store (a projection that mirrors the
write store optimised for reads).

Yagye has **one PostgreSQL database per application** (core_db for Core,
portal_db for Portal). Core does not maintain a separate read model. Portal
IS a read model of Core — but it is a separate application reading via events,
not a CQRS projection within the same application.

The Portal-as-read-model (§17) emerges from the event-driven integration
between the two applications. It is a practical outcome of the architecture,
not the CQRS pattern deliberately applied.

### Why these choices

| Pattern rejected | Why |
|---|---|
| Event Sourcing | Requires replaying events to answer "what is the current balance?" — prohibitive for a ledger with millions of postings. Standard SQL `WHERE id = $id` is better. |
| CQRS (within Core) | Single DB is simpler to operate, easier to reason about transactions, and sufficient at Yagye's scale. |
| Commanded (Elixir ES/CQRS library) | Permanently deferred — see §28 for the full reasoning. |
| Pure request-response | Portal would need direct DB access to Core, creating a coupling that breaks independent deployability. Events are the right integration boundary. |

---

## 28. Why Not Event Sourcing, Commanded, or a Dedicated Event Store

This decision was deliberate and warrants its own section because the
Elixir ecosystem makes event sourcing tempting: the Commanded library is
mature, well-documented, and many Elixir PSPs use it.

### What Commanded provides

Commanded is an Elixir library for CQRS and Event Sourcing:
- **Aggregates** are pure functions that apply commands and emit events
- **Event handlers** receive emitted events and update read models
- **Process managers** coordinate multi-step workflows across aggregates
- **Event store** (typically EventStoreDB or Postgres-backed) is the source of truth

The appeal: a payment aggregate emits `PaymentCreated`, `PaymentDispatched`,
`PaymentSucceeded` events. The full history of any payment is in the event log.
Audit trail comes for free. Temporal queries ("what did this payment look like
at 14:32 on day X?") are exact.

### Why Yagye deferred it permanently

**1. Projection rebuild cost in a financial system**

When a bug is found in a projection (e.g. a balance calculation was wrong),
event sourcing requires rebuilding the projection by replaying all events. For
a ledger with 10 million postings accumulated over 2 years, a full replay is
hours of downtime or a carefully managed online rebuild. The alternative —
keeping a snapshot of aggregate state alongside the event log — reintroduces
the complexity of state management that event sourcing was supposed to eliminate.

**2. The ledger already provides the audit trail**

The primary reason to adopt event sourcing in a PSP is the audit trail —
being able to prove every state transition. Yagye's double-entry ledger
already provides this at the financial level. Every debit and credit is
immutable with a bigserial sequence number. The `payment_attempts` table
has `aggregate_version` for ordering. The `outbox_events` table is the event
log for integration. The audit need is met without event sourcing.

**3. Point-in-time queries are solved by SCD Type 2**

The second reason for event sourcing is temporal queries ("what was a
merchant's fee tier on July 15?"). Yagye's Gold layer uses SCD Type 2
(`valid_from`/`valid_to`) for exactly this. For operational queries on
Core, audit logs (`merchant_status_changes`, `pricing_rule_activations`)
capture changes with timestamps. No event replay required.

**4. The operational database is already PostgreSQL**

Commanded with an event store requires either EventStoreDB (a separate
service to operate) or a Postgres-backed event store (which means Core's
state and the event log compete for the same connection pool). Either way,
it adds operational complexity. Yagye's current stack is already at the
complexity limit for a founding engineering team:

```
PostgreSQL (core_db)
PostgreSQL (portal_db)
Redpanda
RabbitMQ
Oban (PostgreSQL-backed)
```

Adding EventStoreDB is a sixth data store, each requiring backup, monitoring,
patching, and on-call procedures. The marginal benefit does not justify the
operational cost.

**5. The outbox pattern already gives semantic events**

The `outbox_events` table and the `OutboxRelayWorker` provide everything
Commanded's event publishing gives: semantic domain events, transactional
atomicity, and guaranteed delivery. The difference is that in Commanded,
events ARE the source of truth. In Yagye, events are derived from the state
table and published for integration. The practical difference for Portal
(which only reads events) is zero.

### When to reconsider

Commanded becomes attractive if:
- The number of cross-aggregate workflows grows beyond what Oban sagas can
  manage (currently: payment authorisation, settlement, dispute resolution)
- Temporal replay becomes necessary for regulatory audit (BoG requests to
  reconstruct the exact state of a merchant account at a specific timestamp)
- The team grows to a size where aggregate isolation (one Commanded aggregate
  per domain boundary) provides meaningful codebase organisation benefits

---

## 29. Message Brokers — Redpanda and RabbitMQ

### Taxonomy: broker vs queue vs event stream

These three terms are often used interchangeably but mean different things:

| Term | What it is | Example |
|---|---|---|
| **Message queue** | An ordered buffer — messages wait until a consumer picks them up. Simple, no routing logic. | Oban's `oban_jobs` table; Amazon SQS; a Redis list |
| **Message broker** | A routing intermediary — accepts from producers, applies routing rules, delivers to one or more queues. Contains queues but is not itself a queue. | RabbitMQ (AMQP), ActiveMQ |
| **Event streaming platform** | An immutable distributed log — consumers read from any offset and replay history. Messages are not "consumed and gone." | Redpanda, Apache Kafka, Apache Pulsar |

Yagye uses one of each in the latter two categories:

```
┌────────────────────────────────────────────────────────────────────────┐
│  TWO SYSTEMS, TWO MODELS                                                │
│                                                                        │
│  Core ──► Redpanda ──────────────────────────► Portal (read model)    │
│           (event streaming log)                (Karafka consumer)      │
│                                                                        │
│  Core ──► RabbitMQ ──────────────────────────► Merchant webhook        │
│           (AMQP message broker, per-merchant   (HTTP delivery)         │
│            queues inside the broker)                                   │
└────────────────────────────────────────────────────────────────────────┘
```

### Redpanda (Core → Portal integration)

Redpanda is a Kafka-compatible distributed event streaming platform written
in C++ (not JVM). It exposes the Kafka protocol, which means every Kafka
client library — including Karafka (the Ruby consumer framework) — works
with it without modification.

**Why Redpanda over Kafka:**

| | Apache Kafka | Redpanda |
|---|---|---|
| Runtime | JVM (Java/Scala) | Native C++ |
| Dependencies | Requires ZooKeeper (pre-3.x) or KRaft (3.x+) | None — single binary |
| Latency | ~5ms median | ~1ms median |
| Operational complexity | High (broker + ZooKeeper/KRaft + Schema Registry) | Low (single binary per node) |
| Kafka compatibility | Native | 100% protocol-compatible |

At Yagye's scale, Redpanda's operational simplicity is the deciding factor.
Running Kafka requires managing ZooKeeper or KRaft consensus alongside the
brokers. Redpanda is one binary — it handles its own consensus internally.
The team does not pay the Kafka operational tax for a Kafka-level feature set.

**Topic design:**

```
yagye.payments.events        — payment lifecycle events
yagye.merchants.events       — merchant onboarding, KYB status changes
yagye.settlements.events     — settlement batch events
yagye.disputes.events        — chargeback and dispute events
yagye.api_keys.events        — API key created, rotated, revoked
```

One topic per domain aggregate. Portal subscribes to the topics relevant
to its read model. The data platform (Bronze layer) subscribes to all topics.

**Partitioning strategy:**

Each topic is partitioned by `merchant_id`. This ensures all events for a
given merchant arrive at the same partition, in order. Portal's Karafka
consumer group assigns one partition per consumer worker — within a partition,
ordering is guaranteed. Cross-merchant ordering is not required.

Why `merchant_id` and not `payment_id`? Because Portal's read model is
merchant-scoped. A projection worker updating `portal_db.payments` for
merchant `mch_abc` should process all of `mch_abc`'s events in order.
If events were partitioned by `payment_id`, the same merchant's events could
land in different partitions and be processed out of order.

**Consumer group: Portal**

```
Group: yagye-portal
Consumer: PaymentEventsConsumer  → subscribes to yagye.payments.events
Consumer: MerchantEventsConsumer → subscribes to yagye.merchants.events
Consumer: SettlementEventsConsumer → subscribes to yagye.settlements.events
Consumer: DisputeEventsConsumer  → subscribes to yagye.disputes.events
Consumer: ApiKeyEventsConsumer   → subscribes to yagye.api_keys.events
```

Each consumer is a Karafka consumer class. Karafka manages the Kafka protocol
(offset commits, rebalancing, heartbeats). The consumer calls the ACL
(§9b) and passes the normalised payload to the projection worker.

**Consumer group: Data Platform**

```
Group: yagye-data-platform
Consumer: BronzeIngestConsumer → subscribes to all topics
                                  writes raw payloads to S3 Bronze
```

This consumer group is independent of Portal. It processes the same events
from the beginning of the log — Redpanda delivers events to each consumer
group independently. A slow data platform consumer does not affect Portal's
consumer lag.

**Why Redpanda Connect (not a custom consumer) for the data platform:**

The data platform does not need any transformation logic at ingestion —
Bronze is raw and immutable. Redpanda Connect is a purpose-built S3 sink
connector: it reads from a topic, batches records by time window, and writes
Parquet files to S3. Writing a custom consumer for this is reinventing a
solved problem.

### RabbitMQ (Core → Merchant webhooks)

**Broker vs queue — the distinction:** RabbitMQ is a **message broker**, not
a queue. A queue is a simple ordered buffer that holds messages in sequence
until a consumer picks them up (Oban's jobs table is a queue; Amazon SQS is
a managed queue). A message broker is a routing intermediary — it accepts
messages from producers, applies routing rules, and delivers them to the
appropriate queues. RabbitMQ *contains* queues but it is not itself a queue.
The architecture inside RabbitMQ has three layers:

```
Producer  →  Exchange (routing point)  →  Binding rule  →  Queue  →  Consumer
```

The exchange decides which queues receive a message based on the message's
routing key and the binding configuration. This routing layer is what makes
RabbitMQ a broker rather than a bare queue.

RabbitMQ speaks AMQP (Advanced Message Queuing Protocol) — a binary wire
protocol with guaranteed delivery semantics, acknowledgements, and flow control
built into the protocol itself (not bolted on at the application layer).

RabbitMQ is used exclusively for outbound merchant webhook delivery — events
that cross the Yagye → merchant boundary.

**Why RabbitMQ and not Redpanda for webhooks:**

| | Redpanda (Kafka-model) | RabbitMQ |
|---|---|---|
| Consumption model | Consumer group pulls from a log | Queue pushes to consumer |
| Per-consumer queuing | No — one log, many consumer groups | Yes — one queue per merchant |
| Message routing | Topic + partition key | Exchange → binding → per-entity queue |
| Dead-letter handling | Separate DLX topic + manual retry | Native DLX + per-queue DLQ |
| Push semantics | No (consumer polls) | Yes (broker pushes to consumer) |

Webhook delivery requires **per-merchant isolation**: if a merchant's webhook
endpoint is down, their delivery queue backs up without affecting other
merchants. This is natural with RabbitMQ's per-merchant queue model. With
Redpanda, achieving per-merchant isolation would require either one topic per
merchant (unscalable) or a stateful consumer that routes events into per-merchant
buffers in application code (reimplementing queuing in application logic).

**Exchange → queue topology:**

```
Exchange: yagye.webhook.events  (fanout or topic, based on merchant routing key)
    │
    ├── Queue: yagye.webhooks.mch_abc  (one per active webhook endpoint)
    │         DLX: yagye.webhooks.dlx
    │
    ├── Queue: yagye.webhooks.mch_def
    │         DLX: yagye.webhooks.dlx
    │
    └── ...
```

**Broadway consumer:**

Core's `WebhookFanoutWorker` publishes to the exchange. A Broadway consumer
(GenServer-based, running in Core) reads from each merchant queue and calls
the merchant's webhook endpoint via HTTP. Broadway consumers always ack
(even on HTTP failure) — retries are managed by `WebhookDeliveryRetryWorker`
(Oban), not by RabbitMQ redelivery. This prevents RabbitMQ from retrying
failed deliveries at its own cadence, which would conflict with Oban's
backoff schedule.

**Dead-letter exchange (DLX):**

After 10 Oban retry attempts with no success, the delivery is moved to the
DLX queue. The DLX is monitored by the ops team. Messages accumulate there
until an operator either manually re-queues them (after the merchant has
fixed their endpoint) or discards them after investigation.

### Producers and consumers

| Event | Producer | Transport | Consumer |
|---|---|---|---|
| Payment lifecycle event | Core `OutboxRelayWorker` | Redpanda | Portal `PaymentEventsConsumer` + Bronze ingest |
| Settlement event | Core `OutboxRelayWorker` | Redpanda | Portal `SettlementEventsConsumer` + Bronze ingest |
| Merchant webhook | Core `WebhookFanoutWorker` | RabbitMQ | Broadway → merchant HTTPS endpoint |

---

## 30. Event-Driven Architecture: Problems and How Yagye Resolves Them

EDA introduces distributed systems problems that do not exist in a monolith.
Each problem is documented with the concrete solution in Yagye's codebase.

### Problem 1: The dual-write problem

**The problem:** Writing a state change to the database AND publishing an event
to the message broker are two separate operations. If the application crashes
between the two writes, the event is never published — the consumer never learns
about the state change.

**Yagye's solution: Transactional outbox**

The outbox event is written **in the same Ecto.Multi transaction** as the state
change. The message broker is never written to directly during the request.
The `OutboxRelayWorker` reads committed outbox rows and publishes them. If the
relay crashes, it retries from the last unpublished row. The event can be
published more than once (at-least-once delivery) — idempotency in consumers
handles duplicates.

```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:payment, changeset)
|> Ecto.Multi.insert(:outbox, build_outbox_event(payment))
|> Repo.transaction()
# One transaction, both succeed or both roll back.
```

### Problem 2: At-least-once delivery and duplicate events

**The problem:** The relay publishes an event, then crashes before committing
the outbox row as "relayed." On restart, it publishes the event again. The
consumer receives two identical events and projects the same state change twice.

**Yagye's solution: Idempotent consumers**

State projections use **version fencing**: each projection update includes
`WHERE aggregate_version < $new_version` in the update clause. A duplicate
event carries the same `aggregate_version`. The second application of the
update finds no row to update (the version guard rejects it) and succeeds
silently — the projection is unchanged.

Counter projections (aggregates that increment a count) use the
`processed_events` table with a composite primary key of `(event_id, consumer)`.
A duplicate event triggers a unique constraint violation, which the consumer
catches and ignores.

```elixir
# Version fencing for state projections
Repo.update_all(
  from(p in Payment, where: p.id == ^id and p.aggregate_version < ^version),
  set: [status: status, aggregate_version: version]
)
# If version hasn't changed: 0 rows updated. Safe.
```

### Problem 3: Event ordering

**The problem:** Distributed systems do not guarantee message delivery order
across partitions. If a `payment.created` event and a `payment.succeeded` event
land in different partitions, the consumer might process `succeeded` before
`created`.

**Yagye's solution: Partition by merchant_id + version fencing**

All events for a given merchant land in the same Redpanda partition (partitioned
by `merchant_id`). Within a partition, Redpanda guarantees order. Events within
a payment are further ordered by `aggregate_version`. If a consumer receives
`aggregate_version = 3` before version `2` (which should not happen with
per-merchant partitioning but could during rebalancing), the version fencing
guard (`WHERE aggregate_version < $new_version`) handles it: version 3 will
not overwrite version 3 if it arrives again; version 2 arriving late will be
rejected by the guard since the row is already at version 3.

### Problem 4: Consumer lag and backpressure

**The problem:** If Core produces events faster than Portal can consume them,
the Redpanda topic lag grows. An extended lag means Portal's read model is
stale — merchants log in and see payment statuses that are minutes or hours
behind.

**Yagye's solution: Concurrency limits + lag alerting**

Karafka consumer concurrency is tuned to match Portal's PostgreSQL connection
pool. A Grafana alert fires when the consumer group lag exceeds 5,000 events
(configurable). The lag alert triggers ops investigation: either Portal is
under-resourced (scale up consumers) or Core is producing an anomalous spike
(investigate the source).

At very high load, the data platform's Bronze consumer may lag without
affecting Portal — the two consumer groups are independent.

### Problem 5: Schema evolution — breaking event payload changes

**The problem:** Core changes an event payload field name or removes a field.
Portal's ACL (§9b) reads the old field name and gets `nil`. The projection
silently produces wrong data.

**Yagye's solution: Additive-only payload changes + ACL version tolerance**

Core's event payload contract is:
- **Allowed without coordination:** Add new optional fields
- **Requires Portal ACL update first:** Rename an existing field
- **Never allowed:** Remove a required field without a deprecation period

The ACL is written defensively: `@p["field"].presence` instead of
`@p.fetch("field")` for optional fields. Required fields use `fetch` and
will raise immediately if missing — making the breakage visible at the
consumer, not silently producing nil.

When a field is renamed, Core emits **both** the old and new field name for
a deprecation window (typically one release cycle). Portal's ACL is updated
to read the new name; the old name is ignored. After Portal deploys, Core
removes the old field.

### Problem 6: Exactly-once delivery is impossible — so don't try

**The problem:** Distributed systems cannot guarantee exactly-once delivery.
At-most-once (drop duplicates, may lose events) and at-least-once (may
duplicate, never loses) are the options.

**Yagye's approach:** At-least-once delivery (never lose an event) + idempotent
consumers (handle duplicates). This is the correct approach for a financial
system. Losing a `payment.succeeded` event means Portal never marks a payment
as paid — a worse outcome than handling a duplicate event twice.

The outbox gives at-least-once. Idempotency (version fencing + processed_events)
neutralises duplicates. The combination is **effectively exactly-once** for
practical purposes, without the complexity of distributed transactions or
two-phase commit.

### Problem 7: Poison messages — events the consumer cannot process

**The problem:** A malformed event (a Core bug emits `amount: "NaN"`, or the
ACL raises on an unexpected payload shape) causes the consumer to crash. The
consumer retries, crashes again. The message is stuck at the head of the
partition, blocking all subsequent events for that merchant.

**Yagye's solution: Dead-letter consumer + ops alert**

Karafka is configured with a dead-letter topic (`yagye.consumer.dlq`). After
three consecutive processing failures for the same event, Karafka moves the
event to the DLQ and continues processing the next event. The DLQ is monitored
— a Grafana alert fires when the DLQ receives any event. Ops investigates
the malformed event, applies a hotfix to the ACL or projection, and manually
re-publishes corrected events if the projection requires it.

---

## 31. Database Architecture Decisions

### One PostgreSQL instance per application

Yagye runs two PostgreSQL instances:

- `core_db` — owned by Yagye Core (Elixir/Ecto)
- `portal_db` — owned by Yagye Portal (Rails/ActiveRecord)

Portal does **not** have a connection to `core_db`. It learns about Core's
state exclusively through Redpanda events. This boundary is enforced by
configuration — Portal has no `core_db` connection string — not just by convention.

**Why separate databases:**

1. **Independent deployability.** Core and Portal can be deployed, migrated,
   and scaled independently. A Core schema migration does not lock Portal.
2. **Isolation.** A slow Portal analytics query cannot lock a Core payment
   row.
3. **Ownership.** Portal's schema reflects Portal's read model needs — it
   is not a mirror of Core's schema. Portal has columns Core does not have
   (`last_login_at`, `totp_secret`, `session_tokens`) and lacks columns Core
   has (`aggregate_version`, `idempotency_key`, `error_class`).

### Why PostgreSQL and not an alternative

**Why not MySQL:**
- Oban requires PostgreSQL. Oban uses `pg_advisory_locks` for job locking and
  `LISTEN/NOTIFY` for job scheduling. These are PostgreSQL-specific features
  with no MySQL equivalent.
- PostgreSQL's `CHECK` constraints are enforced on every write (used for
  mode isolation, SoD checks). MySQL silently ignores `CHECK` constraints
  in older versions.
- The `EXCLUDE` constraint (used for `processed_events` deduplication) is
  PostgreSQL-specific.

**Why not CockroachDB or Spanner (distributed SQL):**
- Distributed SQL systems sacrifice transaction isolation to achieve horizontal
  scale. CockroachDB's serialisable isolation has higher latency than
  PostgreSQL's for the single-region case (all Yagye infrastructure is in one
  region initially).
- The double-entry ledger's sum-zero constraint is a deferred trigger
  (`DEFERRABLE INITIALLY DEFERRED`). CockroachDB does not support deferred
  triggers.
- At Yagye's volume (thousands of payments per day, not billions), vertical
  scaling of a single PostgreSQL instance is the correct economic choice.
  Horizontal scaling introduces distributed transaction complexity that is not
  warranted.

**Why not MongoDB or another NoSQL store:**
- NoSQL databases sacrifice ACID multi-document transactions for write
  scalability. The double-entry ledger requires atomicity across multiple rows
  (the ledger_entries row + its ledger_postings rows + the running balance
  update) in a single transaction. MongoDB's multi-document transactions exist
  but are slower and carry replica set coordination overhead.
- Foreign keys are critical to Yagye's referential integrity model. MongoDB
  has no foreign keys — integrity is enforced at the application layer, which
  is error-prone in a financial system.
- The sum-zero deferred trigger cannot be expressed in MongoDB. It would have
  to be implemented as application-level validation, running inside the same
  "transaction" — which does not exist in the same form.

**Why not SQLite:**
- SQLite is single-writer. Oban requires concurrent writes from multiple job
  workers. Multiple Phoenix request processes writing simultaneously to a single
  SQLite file would serialise on the write lock.
- No `LISTEN/NOTIFY` support.

### Connection pooling — PgBouncer

Each application connects to PostgreSQL through **PgBouncer** in
transaction-mode pooling:

```
Core (Ecto pool: 20 connections)
  │
  └── PgBouncer (transaction mode)
        │
        └── PostgreSQL (max_connections: 200)
```

Transaction-mode pooling means a database connection is held only for the
duration of a single transaction. Between transactions, the connection is
returned to the pool. This allows Yagye to run 200 Oban workers, 50 Phoenix
request processes, and 10 Karafka consumer processes — all sharing 20 physical
PostgreSQL connections.

**Why transaction mode and not session mode:**

Session mode holds a connection for the lifetime of an application session.
With 260 concurrent processes (workers + request handlers + consumers), session
mode would require 260 PostgreSQL connections — PostgreSQL's memory overhead
per connection is ~10MB, meaning 260 connections consume 2.6GB of RAM before
any query work. Transaction mode reduces this to ~20 connections.

The cost: session mode supports `LISTEN/NOTIFY` (which Oban uses for job
scheduling). The solution is a dedicated connection pool (`oban_notifier_pool`)
with session mode, separate from the main Ecto pool. Oban's notifier holds
one session-mode connection for `LISTEN/NOTIFY`; all other DB work uses the
transaction-mode pool.

### Read replicas

PostgreSQL supports streaming replication — a read replica receives a
continuous stream of WAL (write-ahead log) from the primary and applies it,
maintaining a consistent copy of the database.

At Yagye's current scale, a read replica is not required — the primary handles
both writes and the read workload for the API and portal. A replica is planned
for Phase 18 to serve:

1. **Reporting queries** — the ops team's settlement reconciliation reports
   run against the replica, not the primary, preventing a slow report from
   holding locks on payment rows.
2. **ML training data extraction** — the ML pipeline's feature extraction
   queries run against the replica. (At P20+, this moves to Gold Parquet
   entirely, removing the need for a replica for ML.)

The read replica introduces **replication lag**: replica data is typically
10–100ms behind the primary. The API always reads from the primary to avoid
serving stale data immediately after a write. The read replica is only used
for workloads that can tolerate eventual consistency (reports, analytics).

### Schema migrations

Both applications use their respective migration tools:

- **Core:** `mix ecto.migrate` — Ecto migrations, run at deployment
- **Portal:** `rails db:migrate` — ActiveRecord migrations, run at deployment

**Critical rule:** All production migrations must be **backwards-compatible**.
The deployment sequence is:
1. Deploy Core with migration (schema change applied)
2. Old Core code runs against new schema (must be compatible)
3. New Core code activates (cutover)

A migration that removes a column while old code still reads it will cause
errors during the deployment window. The discipline: add columns freely, but
remove them only after all code references are removed and deployed.

Yagye uses `strong_migrations` (Rails gem) and custom Ecto migration checks
to enforce backwards compatibility — adding `NOT NULL` columns without defaults,
renaming columns, and dropping in-use indexes are all flagged before deployment.

---

## Further Reading

| Document | What it covers |
|---|---|
| [system-overview.md](system-overview.md) | Component topology, API surfaces, security model summary |
| [payment-flow.md](payment-flow.md) | Step-by-step payment lifecycle from API call to ledger settlement |
| [data-flow.md](data-flow.md) | How data moves: outbox → projections → webhooks |
| [docs/adr/](../adr/README.md) | All 26 Architecture Decision Records — the definitive "why" for each choice |
| [docs/roadmap/remaining-features.md](../roadmap/remaining-features.md) | Every deferred feature: prerequisites, implementation approach, PSP relevance |
| [docs/data-engineering/README.md](../data-engineering/README.md) | Lakehouse architecture, Floci, DuckDB, Redpanda Connect |
| [docs/data-engineering/ml-architecture.md](../data-engineering/ml-architecture.md) | The four ML models: routing predictor, risk scorer, reserve recommender, churn predictor |
| [docs/schema/yagye-core.dbml](../schema/yagye-core.dbml) | Full Core database schema |
| [docs/schema/yagye-portal.dbml](../schema/yagye-portal.dbml) | Full Portal database schema |
