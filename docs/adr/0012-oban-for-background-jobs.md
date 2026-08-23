# ADR-0012: Oban for Background Job Processing

**Date:** 2026-08-19
**Status:** Accepted

## Context

Phase 2 introduced asynchronous work: a payment intent is created synchronously
(returns immediately to the caller), then dispatched to a provider in the background.
The system needed a durable job queue that could survive process crashes and
application restarts without losing work.

Three options were considered:

**Option A — vanilla GenServer / Task.Supervisor**: simple to implement, zero
dependencies. The problem: state lives in memory. A node crash between job creation
and execution silently drops the work. There is no retry, no dead-letter, no
observability. Acceptable for fire-and-forget notifications; unacceptable for
financial transactions.

**Option B — a message broker (RabbitMQ, Kafka)**: durable and battle-tested for
high-throughput fan-out. The problem: requires a separate infrastructure component,
a producer/consumer protocol, at-least-once delivery semantics that the application
must handle, and operational expertise in a second system before the first merchant
has been onboarded. Premature at this stage.

**Option C — Oban**: PostgreSQL-backed job queue for Elixir. Jobs are rows in an
`oban_jobs` table. Inserting a job and the state change that triggers it happens in
the same database transaction. If the transaction rolls back, the job does not exist.
If the node crashes before completing the job, the row is still there and another
node picks it up.

## Decision

Use **Oban** for all background job processing in `yagye_core` (and `yagye_simulator`
where async work is needed).

- Every Oban worker is a module implementing `Oban.Worker` in the relevant domain's
  `workers/` subdirectory.
- Jobs that must be atomic with a state change are inserted inside the same
  `Ecto.Multi` or `Repo.transaction` block as the state change, using
  `Oban.insert/1` or `Multi.insert/2`.
- Queues are declared in `config.exs` and added as needed:
  `payments`, `events`, `projections`.
- In tests, Oban is set to `testing: :manual` so jobs are never run unless
  explicitly drained with `Oban.drain_queue/1`.

## Consequences

### Positive
- Job enqueue and state change are atomic: no job is created without its trigger,
  and no trigger occurs without its job. This eliminates the "fire and forget and
  hope" pattern.
- Built-in retry, backoff, unique constraints, dead-letter queue, and telemetry.
- No new infrastructure — Oban uses the same Postgres that is already the system
  of record.
- `Oban.Testing` helpers make background job behaviour fully testable without
  running real processes.
- `Oban.Pro` (if licensed later) adds batches, workflows, and rate limiting without
  changing the worker interface.

### Negative / Trade-offs
- `oban_jobs` grows indefinitely if the Pruner plugin is not configured. Must be
  configured from day one.
- Oban is coupled to PostgreSQL. Moving to a different database would require
  replacing the job queue simultaneously — accepted because PostgreSQL is the
  declared system of record (ADR-0006).
- At very high throughput, PostgreSQL-backed queues have lower ceiling than
  dedicated brokers. RabbitMQ is planned for P15 for outbound webhook delivery
  specifically; Oban remains for all internal domain work.
