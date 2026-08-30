# Scaling Playbook

This document captures known scaling pressure points in the Yagye architecture,
when each concern becomes load-bearing, and the specific remediation for each.
It is a living reference — add entries as new pressure points are identified.

---

## 1. Read-Model Table Bloat

### What it is

The portal's read-model tables (`payments`, `portal_webhook_deliveries`, etc.)
are populated by Karafka consumers processing events from Redpanda. They grow
indefinitely. No record is ever hard-deleted (ADR-0020). At moderate merchant
volume (e.g. 100 merchants × 10k txns/day), the `payments` table accumulates
~36M rows/year.

### Near-term mitigation (current — in place)

Every portal query object that reads from high-volume tables enforces a default
date-range window (30 days) when no explicit filter is supplied. Unbounded
full-table scans do not reach the DB. Composite indexes on
`(merchant_code, mode, created_at DESC)` serve the common filtered queries.

### Medium-term: PostgreSQL range partitioning

Partition high-volume tables by `created_at` with monthly partitions:

```sql
CREATE TABLE payments (
  ...
  created_at timestamptz NOT NULL
) PARTITION BY RANGE (created_at);

CREATE TABLE payments_2026_08 PARTITION OF payments
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
```

A query with `WHERE created_at >= '2026-08-01'` touches only the August
partition via partition pruning — the planner does not scan older partitions.

**When to do it:** When the `payments` table exceeds ~10M rows or when query
planner explain plans show sequential scans despite the composite index.

**Operational procedure:**
1. Create next month's partition on the last day of the current month (cron).
2. Detach partitions older than the retention window (e.g. 24 months) and move
   to a cold-storage read-replica or S3 via `pg_dump --table`.
3. The hot partition table stays small; historical queries hit the archive.

### Long-term: rollup tables for aggregates

Dashboard queries (`VolumeSummaryQuery`, chart data) currently scan the raw
`payments` table for the current month. A rollup table eliminates this:

```sql
CREATE TABLE merchant_daily_rollups (
  merchant_code   text        NOT NULL,
  date            date        NOT NULL,
  currency        text        NOT NULL,
  provider        text,
  mode            text        NOT NULL,
  total_count     integer     NOT NULL DEFAULT 0,
  success_count   integer     NOT NULL DEFAULT 0,
  total_amount    bigint      NOT NULL DEFAULT 0,
  PRIMARY KEY (merchant_code, date, currency, provider, mode)
);
```

A nightly Oban job (`DailyRollupWorker`) rewrites each merchant's row for
yesterday — a recompute-from-source (idempotent, not incremental, matching the
`DailyMetricsWorker` pattern from ADR-0015). Dashboard queries then read
`WHERE date >= 30.days.ago` on a ~3,000-row result set instead of millions.

**When to do it:** When `VolumeSummaryQuery` explain plans show seq scans or
execution time exceeds 200ms on production-sized data.

---

## 2. Horizontal Scaling of the Core API

### What it is

`yagye_core` is a Phoenix application. Running multiple instances behind a
load balancer is the primary horizontal scaling path. Most of the application
is stateless (HTTP handlers, Ecto queries, Oban workers) and scales naturally.
Three components require attention at multi-node deployment:

### 2a. Rate limiting

Current implementation uses an in-process ETS table. This is correct for a
single node — ETS is fast and persistent across requests. On multiple nodes,
each node has an independent counter: a merchant can make N requests to node 1
and N requests to node 2, bypassing the intended limit.

**Fix (P17):** Replace ETS rate limiting with Redis-backed counters using the
`hammer` library with the `Hammer.Backend.Redis` adapter. Redis is the single
source of truth across all nodes. Rate limit state survives node restart.

```elixir
# config/runtime.exs
config :hammer,
  backend: {Hammer.Backend.Redis, [
    expiry_ms: 60_000,
    redix_config: [host: System.get_env("REDIS_HOST")]
  ]}
```

**When to do it:** Before deploying a second core node. Single-node deployments
are safe with ETS.

### 2b. Idempotency

Current implementation uses `idempotency_keys` table in PostgreSQL. This is
inherently multi-node safe — all nodes share the same DB. No change needed.

The `SELECT ... FOR UPDATE` lock in the idempotency check serialises concurrent
duplicate requests at the DB level regardless of which node receives them.

### 2c. Oban background jobs

Oban is backed by PostgreSQL and is designed for multi-node operation. Multiple
nodes can poll the same `oban_jobs` table; Oban uses `SELECT ... FOR UPDATE
SKIP LOCKED` to prevent double-execution. No configuration change is needed for
basic multi-node.

**Watch for:** Queue-level concurrency. If 4 nodes each run 10 workers on the
`payment_dispatch` queue, effective concurrency is 40. Review queue `limit`
settings in `config/config.exs` before scaling node count.

### 2d. Phoenix PubSub / Solid Cable

The portal uses Solid Cable for real-time updates (balance refreshes, payment
state changes). Solid Cable stores subscription state in PostgreSQL and uses
`LISTEN/NOTIFY` for message delivery. This is multi-node safe by design — all
portal nodes share the same Postgres LISTEN channel.

Core's Phoenix PubSub is used for internal process communication (not exposed
externally). The default `Phoenix.PubSub.PG2` adapter propagates messages
across Erlang nodes in a cluster. If running in a Kubernetes environment without
Erlang clustering, switch to `Phoenix.PubSub.Redis` adapter.

**When to do it:** When running more than one core node and Erlang distribution
(libcluster) is not configured.

---

## 3. Outbox Relay Under Load

### What it is

The outbox relay (ADR-0014) polls `outbox_messages` and dispatches Oban jobs.
At high throughput, the relay can fall behind if the batch size or poll interval
is too conservative.

### Tuning levers

| Parameter | Location | Default | Direction |
|---|---|---|---|
| `@batch_size` | `OutboxRelayWorker` | 100 | Increase to reduce poll overhead |
| Poll interval | Oban queue schedule | 1s | Decrease for lower latency |
| Queue concurrency | Oban config | 5 | Increase to parallelise dispatch |

### Monitoring signal

`last_applied_at` on `proj_merchant_balances` surfaces projection staleness in
the portal UI. If this timestamp consistently lags by more than 5 seconds, the
relay is behind. Check Oban queue depth first — a backlog there is the primary
indicator.

### Long-term: migrate hot events to Redpanda

High-volume events (payment state changes, ledger postings) should move from
the outbox → Oban path to direct Redpanda production at P14. Redpanda handles
millions of events/second; the outbox pattern is a bootstrapping strategy for
before a message broker is in place, not a permanent architecture for
production-volume event streaming.

---

## 4. Database Connection Pooling

### What it is

Each `yagye_core` node holds a pool of PostgreSQL connections (via `Ecto` +
`postgrex`). Default pool size is 10. PostgreSQL has a hard connection limit
(typically 100 on managed services like Render/Fly.io, higher on RDS).

With N nodes × 10 pool size, total connections = 10N. At 5 nodes, that is 50
connections — manageable. At 20 nodes, it is 200 — exceeding most managed
limits.

### Fix: PgBouncer

Deploy PgBouncer in transaction-pooling mode between the application nodes and
PostgreSQL. PgBouncer multiplexes many application connections onto a small
number of real DB connections.

```
app nodes (20 × 10 pool = 200 connections)
    → PgBouncer (transaction mode, pool_size=20)
    → PostgreSQL (20 real connections)
```

**When to do it:** When total connections (nodes × pool_size) approaches 80%
of the DB connection limit.

**Caveat:** Transaction-mode PgBouncer does not support `LISTEN/NOTIFY` or
advisory locks held across transactions. Solid Cable and any advisory-lock
usage must connect to PostgreSQL directly (bypass PgBouncer) or use session
pooling mode for those specific connections.

---

## 5. Simulator and Portal Scaling

The gateway simulator (`yagye_gateway_simulator`) is a test/development tool.
It should not be exposed in production; no scaling concern applies.

The portal (`yagye_portal`) is a Rails application used by ops and merchants.
It is read-heavy (dashboard, transaction history). Standard Rails scaling
applies:

- **Multiple Puma workers/threads** per instance — tune based on CPU and DB
  connection budget.
- **Karafka consumer nodes** can be scaled independently of the web process.
  Run consumer groups on dedicated nodes to avoid competing with HTTP workers
  for CPU during high-throughput event ingestion.
- **Solid Cache** (Rails cache store) uses SQLite by default in development.
  In production, configure to use the shared PostgreSQL database or Redis to
  share cache across portal instances.

---

## Summary: When to Act

| Concern | Act when | Action |
|---|---|---|
| Read-model table bloat | `payments` > 10M rows | Range partitioning on `created_at` |
| Dashboard aggregate scans | Query > 200ms | Rollup tables + `DailyRollupWorker` |
| Rate limiting across nodes | Deploying second core node | Redis-backed Hammer |
| DB connection exhaustion | Connections > 80% of limit | PgBouncer (transaction mode) |
| Oban relay lag | `last_applied_at` lags > 5s | Increase batch size / queue concurrency |
| Hot event volume | Outbox throughput becomes bottleneck | Redpanda direct production (P14) |
| Phoenix PubSub across nodes | Multi-node without Erlang clustering | Redis PubSub adapter |
