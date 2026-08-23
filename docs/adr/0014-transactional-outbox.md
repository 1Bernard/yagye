# ADR-0014: Transactional Outbox for Domain Event Emission

**Date:** 2026-08-23
**Status:** Accepted

## Context

Phase 7 required publishing domain events (payment.created, payment.succeeded,
merchant.approved, etc.) to downstream consumers such as projection workers. The
core invariant is: **an event must be published if and only if its triggering state
change committed**. Two naive approaches fail this:

**Dual-write**: write the state change to Postgres and publish the event to a
message bus in the same code path. The problem: if the process crashes between the
two writes, the state change commits but no event is published (or vice versa).
There is no distributed transaction that spans a database and a message broker.

**Publish inside the transaction**: open a DB transaction, write the state change,
publish the event to the bus, commit. The problem: the bus call succeeds but the DB
transaction rolls back, and the event was already delivered. Duplicate events for
failed writes.

The transactional outbox pattern solves this by removing the message bus entirely
from the hot path.

## Decision

All domain events are written to an **`outbox_messages` table in the same database
transaction as the state change**:

```elixir
Multi.new()
|> Multi.update(:payment, ...)
|> Multi.insert(:outbox, fn %{payment: p} ->
     Outbox.build_changeset(p, "payment.succeeded", %{...})
   end)
|> Repo.transaction()
```

A separate `OutboxRelayWorker` (Oban cron, every minute) reads unpublished rows
in insertion order and dispatches them to projection workers, marking each row
`published_at` on success.

Key properties of the implementation:

- `outbox_messages.id` is `bigserial` — the relay reads `WHERE published_at IS NULL
  ORDER BY id LIMIT n`, which is efficient without a secondary index scan.
- `outbox_messages.event_id` is a UUIDv7 — the consumer dedupe key. Projection
  workers must be idempotent on `event_id`.
- `Outbox.build_changeset/4` returns an `%Ecto.Changeset{}` without inserting.
  Use it with `Multi.insert/3`. `Outbox.emit/4` is a thin wrapper for direct
  inserts (tests, simple callers).
- `destination` is a data field (`"internal:projections"`), not code. Routing
  the same event to Kafka later is a config change, not a code change.

## Consequences

### Positive
- The state change and the event record are atomic. A rollback means no event; a
  commit means an event always exists to be delivered. Dual-write is structurally
  impossible.
- No message broker is needed in the critical path. The relay is a background
  process; provider latency does not affect event delivery latency.
- The `outbox_messages` table is an audit log of every domain event, with
  `published_at`, `publish_attempts`, and `last_error` visible in the database.
- `OutboxRelayWorker` self-reschedules immediately on a full batch (backpressure),
  and falls back to the cron schedule when idle.

### Negative / Trade-offs
- Events are delivered asynchronously — projection workers see `payment.succeeded`
  a few seconds after commit, not sub-millisecond. Projections must not be used
  where strongly-consistent reads are required.
- The relay is a single writer per shard. At very high event volumes a partitioned
  relay (by `partition_key`) would be needed. Deferred to P14 (Kafka).
- `OutboxRelayWorker` must handle its own idempotency: re-delivering an already-
  published event (e.g. after a relay crash mid-batch) must not cause side effects.
  Downstream workers enforce this via `event_id` dedup.
