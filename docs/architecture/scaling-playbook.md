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

The original single-node implementation used an in-process ETS table. On
multiple nodes, each node had an independent counter, allowing a merchant to
bypass per-node limits.

**Done in P17:** Replaced ETS rate limiting with Redis-backed distributed
counters using the `hammer` library with `Hammer.Backend.Redis`. Redis is the
single source of truth across all nodes. Rate limit state survives node restart.

```elixir
# config/runtime.exs
config :hammer,
  backend: {Hammer.Backend.Redis, [
    expiry_ms: 60_000,
    redix_config: [host: System.get_env("REDIS_HOST")]
  ]}
```

Multi-node deployments are safe. Single-node deployments remain valid — Redis
overhead is negligible compared to the HTTP round-trip.

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

### 2e. Settlement Scheduler — Multi-Node Race Condition

**Single-node: safe.** The `SettlementSchedulerWorker` queue has concurrency = 1.
Only one job runs at a time, so the guard check and batch insert are effectively
serialised.

**Multi-node: race exists.** When two nodes each start a `SettlementSchedulerWorker`
for the same `{merchant_id, provider_id, currency, mode}` combination, both can
pass the `guard_no_open_batch` check (a `SELECT EXISTS` read) before either
inserts. The node that inserts second hits the unique constraint on
`settlement_batches` and returns `{:error, :batch, %Ecto.Changeset{}, _}`.

The current `unwrap_batch_result/1` does not match this tuple — it falls
through to a `FunctionClauseError`. `dispatch_batch/4` then crashes with an
unhandled error, and Oban retries the job unnecessarily.

**Fix — 15 minutes, must apply before deploying a second Core node:**

In `apps/yagye_core/lib/yagye_core/settlement/settlement.ex`, add one clause
to `unwrap_batch_result/1` **above** the generic changeset clause:

```elixir
# Multi-node: unique constraint violation on period_start means another node
# already created the batch — treat as :batch_already_open, not an error.
defp unwrap_batch_result({:error, :batch, %Ecto.Changeset{} = cs, _}) do
  if cs.errors[:period_start] != nil do
    {:error, :batch_already_open}
  else
    {:error, cs}
  end
end
```

`dispatch_batch/4` already handles `{:error, :batch_already_open}` by
returning `:skip`, so no further changes are needed.

**Optional — Oban `:global` engine for cron deduplication:**

The Oban `:basic` engine (default) enqueues cron jobs on every node
independently. With two nodes, `SettlementSchedulerWorker` can run twice per
trigger even with the race fix in place (the second run simply returns `:skip`).
This is harmless but noisy. To eliminate it, switch the cron queue to the
`:global` engine:

```elixir
# config/config.exs
config :yagye_core, Oban,
  engine: Oban.Pro.Engines.Smart,  # or Oban.Pro.Engines.Global if licensed
  ...
```

Without the Pro engine, an alternative is to route the settlement cron job
through a separate single-concurrency Oban queue and ensure only one node
processes that queue by affinity (available in ECS via task placement
constraints). The `:basic` engine + race fix is sufficient for initial
multi-node launch.

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

## 6. When to Add a Second Node / Load Balancer

This section answers: "what specifically changes when the app needs to run on
more than one server?"

---

### 6.1 Trigger signals — when to scale

| Signal | Threshold | Service |
|---|---|---|
| CPU sustained above 70% | > 15 minutes | Core API or Portal |
| HTTP P95 response time | > 500ms | Core API or Portal |
| Oban queue depth | > 500 jobs backlogged | Core API |
| Karafka consumer lag | > 10,000 messages | Portal consumers |
| DB connections | > 80% of limit | Any |

A single burst is not a trigger. These thresholds are sustained over a 15-minute
window (one Grafana evaluation period).

---

### 6.2 Core API (`yagye_core`) — stateless, horizontally safe

The Core API process (`Phoenix`/`Bandit`) is fully stateless at the HTTP layer.
Add a second node and put an ALB (AWS Application Load Balancer) or nginx in
front. No sticky sessions needed — every request carries its own API key or
JWT for authentication.

**What to configure when adding node 2:**

| Item | Action |
|---|---|
| Load balancer health check | `GET /api/v1/health` → 200 |
| Oban queue concurrency × node count | Recalculate — see § 2c |
| Settlement scheduler race fix | Apply `unwrap_batch_result` clause — see § 2e |
| Phoenix PubSub | Add `libcluster` for Erlang clustering, or switch to Redis PubSub adapter — see § 2d |
| Rate limiting | Already done (Redis/Hammer — see § 2a) |
| Idempotency | Already safe (PostgreSQL — see § 2b) |
| Redis connection | Confirm `REDIS_HOST` is set and reachable from all nodes |

**Oban queue arithmetic (required before adding node 2):**

```
Effective concurrency = concurrency_per_queue × node_count

Example: payment_dispatch concurrency = 10, 2 nodes → 20 concurrent workers
```

Review each queue in `config/config.exs` and ensure the product is within the
safe DB connection budget and downstream PSP rate limits before scaling.

---

### 6.3 Portal (`yagye_portal`) — Rails, mostly stateless

The portal is a Rails 8 application using Puma. It is largely stateless at the
HTTP layer but has two components that need attention.

**Session storage:** Devise uses the Rails session store. In development this is
the cookie store, which is per-request and inherently multi-node safe. Confirm
`config/initializers/session_store.rb` uses `:cookie_store`, not a file or
in-process store.

**Solid Cable:** Uses PostgreSQL `LISTEN/NOTIFY`. Multi-node safe — all portal
nodes share the same Postgres connection and all receive the same NOTIFY. No
change needed.

**Solid Cache:** Configure to use PostgreSQL or Redis, not SQLite, so all portal
nodes share the same cache:

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store  # backed by shared PostgreSQL
```

**Karafka consumers:** Consumer processes should be run on dedicated nodes
separate from the web (Puma) workers. Each consumer node only runs Karafka,
not Puma. Scale consumer nodes independently of web nodes.

**What to configure when adding portal node 2:**

| Item | Action |
|---|---|
| Load balancer health check | `GET /up` → 200 |
| Session store | Confirm `:cookie_store` (stateless) |
| Solid Cache | Switch to PostgreSQL-backed Solid Cache or Redis |
| Karafka | Run on dedicated nodes, not mixed with web workers |
| DB connections | Puma threads × nodes — budget against DB connection limit |

---

### 6.4 Scoring service (`yagye_data/scoring_service`) — single instance is fine until volume

The scoring service (FastAPI + Uvicorn) responds to synchronous scoring
requests from the Core API. At launch, a single instance is sufficient.

Add a second instance when:
- P50 scoring latency exceeds 100ms (the Core API path blocks on it)
- CPU is sustained above 70%

The service is stateless (all model weights are loaded from S3 at startup and
held in memory). Behind an ALB, no sticky sessions are needed. The model
weights are read-only, so multiple instances all load from the same S3 path.

**Note:** If running multiple scoring service instances, all must run the same
model version. The `champion.flag` file in S3 is the single source of truth.
When a new champion is promoted, all scoring service instances must be restarted
(rolling restart works — there is no shared mutable state).

---

### 6.5 Load balancer configuration summary

For AWS ECS + ALB (the target production infrastructure — see P22 Terraform):

```
Internet → ALB (HTTPS :443)
  ├── /api/*              → Core API target group (port 4000)
  ├── /*  (default)       → Portal target group (port 3000)
  └── /score/*            → Scoring service target group (port 8080)
           (internal VPC only — not public)
```

**Health check paths:**
- Core API: `GET /api/v1/health` (returns 200 with `{"status":"ok"}`)
- Portal: `GET /up` (Rails default health endpoint)
- Scoring service: `GET /health`

**Sticky sessions:** Not needed for any service. All session state is in
PostgreSQL (Devise cookies) or Redis (rate limiting). The ALB should use
round-robin routing.

**TLS termination:** At the ALB. Backend services speak plain HTTP inside the
VPC. The ALB certificate covers the production domain.

---

### 6.6 Services that must NOT be scaled horizontally

| Service | Reason |
|---|---|
| Gateway simulator | Test/dev tool only — must not reach production at all |
| ETL pipeline (`etl.py`, `transforms/`) | Currently docker-compose; must become EventBridge Scheduler in production — one scheduled invocation per run, not a persistent service |
| MLflow tracking server | Single-instance metadata store; not in the request path |

---

## Summary: When to Act

| Concern | Act when | Action |
|---|---|---|
| Read-model table bloat | `payments` > 10M rows | Range partitioning on `created_at` |
| Dashboard aggregate scans | Query > 200ms | Rollup tables + `DailyRollupWorker` |
| Rate limiting across nodes | Deploying second core node | Already done (Redis/Hammer § 2a) |
| DB connection exhaustion | Connections > 80% of limit | PgBouncer (transaction mode § 4) |
| Oban relay lag | `last_applied_at` lags > 5s | Increase batch size / queue concurrency § 3 |
| Hot event volume | Outbox throughput becomes bottleneck | Redpanda direct production (P14) |
| Phoenix PubSub across nodes | Multi-node without Erlang clustering | Redis PubSub adapter § 2d |
| Settlement scheduler race | Before adding second Core node | Add `unwrap_batch_result` clause § 2e |
| Core API CPU/latency | P95 > 500ms sustained | Add second Core node — checklist § 6.2 |
| Portal CPU/latency | P95 > 500ms sustained | Add second Portal node — checklist § 6.3 |
| Scoring service latency | P50 > 100ms sustained | Add second scoring instance § 6.4 |
| Karafka consumer lag | > 10k messages sustained | Add dedicated consumer nodes § 6.3 |
