# ADR-0022: Data Platform & Lakehouse Architecture

**Date:** 2026-09-05
**Status:** Accepted

---

## Context

Yagye's operational data lives in two places: the Core PostgreSQL write ledger
and the Portal read-model DB. Both are optimised for transactional workloads —
they are not designed for analytical queries, model training, or long-horizon
trend analysis.

As the platform adds ML-driven routing (P20) and intelligent reserve management,
it needs a place to accumulate event history, compute features, and train models
without touching the production DB.

---

## Decision

### Storage layer: Floci (local) → AWS S3 (production)

All analytical data is written to object storage as partitioned Parquet files.
Locally, Floci emulates the S3 API (`s3://yagye-lake-raw/`). In production,
real S3 buckets replace Floci with no code change — the S3 endpoint URL is
injected at runtime.

Two buckets:
- `yagye-lake-raw` — raw event Parquet, append-only, partitioned by `year/month/day`
- `yagye-lake-curated` — feature tables produced by DuckDB ETL jobs

### Ingestion: Redpanda Connect S3 sink

A Redpanda Connect pipeline consumes the outbox topics published by Core
(`payment.*`, `dispute.*`, `reconciliation.*`, `settlement.*`) and writes
Parquet batches to `yagye-lake-raw`. No custom consumer code — Redpanda
Connect handles schema evolution and backpressure natively.

### Analytics: DuckDB (not Spark / Glue)

DuckDB is the sole query engine for feature extraction and ETL. It reads
Parquet directly from S3 using the `httpfs` extension:

```python
SET s3_endpoint = 'floci:4566';   # locally
SET s3_endpoint = 's3.amazonaws.com';  # production
```

Rationale: DuckDB has identical query behaviour against local Floci and real
S3. No Spark cluster, no Glue job, no EMR — they are too heavy for the data
volumes Yagye will see in its first two years and introduce ops complexity
that is not justified.

### Synthetic data: gateway_simulator load generator

A `mix simulator.generate_load` Mix task fires parameterised payment batches
at Core via the API using deterministic MSISDN prefixes. This produces a
labeled dataset (success / decline / timeout / fraud-burst) for model training
before any real merchant traffic exists.

### Network placement

| Service | Docker network |
|---------|---------------|
| Floci | `data` (DB + Redpanda access) |
| Redpanda Connect sink | `data` |
| DuckDB ETL jobs (Python) | `data` |
| ML scoring service | `core_mesh` (Core must reach it; Portal must not) |

---

## Consequences

- The analytics path has zero read pressure on the Core write DB.
- Local development uses identical code paths as production — no separate
  "dev mode" for data pipelines.
- Parquet + DuckDB format is directly queryable by AWS Athena and Glue if
  the team ever needs a managed service — no migration required.
- Event schemas must be stable before the sink is built. Breaking schema
  changes require a new partition prefix, not a migration.
