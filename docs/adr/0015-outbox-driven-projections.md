# ADR-0015: Outbox-Driven Read-Model Projections

**Date:** 2026-08-23
**Status:** Accepted

## Context

Several read patterns are expensive against the normalised write model:

- "What is a merchant's available balance?" requires summing ledger postings.
- "What is the current state of a payment?" requires joining payments, attempts,
  and events.
- "How many payments succeeded today?" requires an aggregate across the payments
  table.

Running these queries live on every API call is costly and becomes a bottleneck as
volume grows. The system needed a way to maintain pre-computed read models that are
updated as domain events occur.

Three approaches were considered:

**Option A — live queries with materialised views**: PostgreSQL materialised views
refreshed on a schedule. Simple, no additional code. The problem: refresh is not
event-driven — a view refreshed every 5 minutes is 5 minutes stale by definition.
`REFRESH MATERIALIZED VIEW CONCURRENTLY` holds a lock and competes with writes.

**Option B — database triggers**: update projection tables inside the database
trigger on write. Fast and consistent. The problem: logic lives in SQL, outside of
the application's domain model, test suite, and version control discipline. Trigger
code is opaque to Dialyzer, Credo, and ExUnit. A bug in a trigger can corrupt
projections silently.

**Option C — outbox-driven Oban workers**: the relay dispatches an Oban job per
event; each job updates the relevant projection table. Logic lives in Elixir,
tested with ExUnit, visible to static analysis.

## Decision

All read-model projections are updated by **Oban workers triggered by the outbox
relay** (ADR-0014). Each projection worker:

- Receives an `OutboxMessage` struct (the `EventEnvelope` decoded from JSONB).
- Applies idempotency before mutating: version fencing for upserts (apply only if
  `incoming_version > stored_version`), `event_id` dedup for counters (a counter
  increment is not idempotent — dedup is required).
- Uses `ON CONFLICT DO UPDATE` or `INSERT ... ON CONFLICT DO NOTHING` — never a
  read-then-write.

Current projection workers:

| Worker | Table | Strategy |
|---|---|---|
| `PaymentSummaryProjection` | `proj_payment_summaries` | Version fence on `aggregate_version` |
| `MerchantBalanceProjection` | `proj_merchant_balances` | `event_id` dedup before incrementing |
| `DailyMetricsWorker` | `proj_daily_merchant_metrics` | Hourly recompute from source |

`DailyMetricsWorker` uses recompute-from-source rather than incremental update
because daily metric counters are prone to double-counting on replay. A recompute
is idempotent by definition; an increment is not.

## Consequences

### Positive
- Projection logic lives in Elixir: tested, typed, linted, refactorable.
- Version fencing and `event_id` dedup are explicit, visible invariants in the
  worker code — not hidden in trigger SQL.
- Adding a new projection is a new worker module and an outbox `destination` entry.
  No schema changes to the outbox infrastructure.
- Workers are retried automatically by Oban on failure. A projection that fails
  to update does not lose the event — the outbox row is still there.

### Negative / Trade-offs
- Projections are eventually consistent. A query immediately after a state change
  may see the previous projection state. This is acceptable for dashboard reads;
  it is not acceptable for authoritative financial reads (use the write model for
  those).
- If the relay or a projection worker falls behind, projection staleness grows.
  The `last_applied_at` column on `proj_merchant_balances` surfaces this to the UI
  as a freshness indicator.
- Recompute-from-source (`DailyMetricsWorker`) is correct but reads the full day's
  payments on every hourly run. At high volume a partition or incremental approach
  will be needed. Deferred until volume justifies it.
