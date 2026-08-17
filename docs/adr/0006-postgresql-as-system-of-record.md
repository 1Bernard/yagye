# ADR 0006 — PostgreSQL as System of Record

Date: 2026-08-17
Status: Accepted

---

## Context

Yagye is a financial platform. Its core guarantee is that money is never double-counted, never lost, and never created from nothing. Every architectural choice for the persistence layer must be evaluated against that guarantee first, and against convenience or scale second.

Three properties make a database suitable as the system of record for a payment platform:

1. **Strong ACID guarantees** — a payout and its ledger entries must commit or fail atomically. Partial writes are not acceptable.
2. **Constraint enforcement at the database layer** — business rules that protect money integrity (e.g. a posting must balance to zero, a refund cannot exceed the original payment) should be enforced by the database, not only by application code. Application code has bugs; the database is the last line of defence.
3. **Mature ecosystem** — the Elixir/Ecto stack, the Rails stack (for `yagye_portal`), and every third-party tool in the payment space have first-class support for PostgreSQL.

---

## Decision

**PostgreSQL 18** is the system of record for all three applications: `yagye_core`, `yagye_portal`, and `gateway_simulator`. Each application owns its own database; they do not share a schema.

Each database runs as:
- A local Docker container (Postgres 18) in development and CI
- An AWS RDS for PostgreSQL instance in staging and production (provisioned by Terraform)

The same Postgres version is used in all environments. Divergence between local and production Postgres versions has historically been a source of subtle migration bugs.

---

## Why PostgreSQL over the alternatives

**vs MySQL / MariaDB:** PostgreSQL has a richer constraint model (`EXCLUDE`, deferred `CHECK`, partial indexes), JSONB, and a stronger reputation for correctness in the financial/banking sector. The `EXCLUDE` constraint used in `pricing_rules` (only one active rule per merchant per currency at a time) is a PostgreSQL-specific feature.

**vs CockroachDB / distributed SQL:** Yagye is deployed as a single-region service initially. Distributed SQL adds latency to every write (consensus round-trips) in exchange for multi-region availability that we do not yet need. If multi-region becomes a requirement, it is a migration decision made at that point — not one made speculatively today.

**vs NoSQL (DynamoDB, MongoDB):** The double-entry ledger (see ADR-0005) requires joining `ledger_entries` to `ledger_postings` and aggregating balances. Relational algebra is the natural model for this. NoSQL would require application-side joins and would make it trivially easy to introduce accounting errors.

---

## Consequences

**Positive**
- Full ACID transactions across all tables in a single database — ledger entries, postings, and balances commit or roll back together.
- `EXCLUDE` constraints enforce single-active pricing rules at the DB layer.
- `CHECK` constraints enforce non-negative balances, valid currency codes, and status machine transitions without application code.
- JSONB columns (`metadata`, `raw_gateway_response`) store unstructured data without a separate document store.
- `pg_advisory_lock` available for idempotency and concurrency control without an external Redis lock.
- Ecto (`yagye_core`), ActiveRecord (`yagye_portal`), and every standard migration tool support PostgreSQL natively.

**Negative / trade-offs**
- Vertical scaling only within a single region. Horizontal read replicas are possible but write throughput is bounded by a single primary. At the transaction volumes expected in Phase 1 (< 1,000 TPS), this is not a constraint.
- Schema migrations require care — running `ALTER TABLE` on a 50M-row `ledger_entries` table in production requires a zero-downtime migration strategy (adding columns as nullable first, backfilling, then applying constraints).
- Each application has its own database; cross-application queries (e.g. `yagye_core` looking at `yagye_portal` data) must go through the API layer, not a SQL join. This is a feature — it enforces the bounded-context boundary — but it means cross-app reports need an ETL step.
