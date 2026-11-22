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

All analytical data is written to object storage. Locally, Floci (port 4566)
emulates the S3 API. In production, real S3 buckets replace Floci with no code
change — the S3 endpoint URL is injected at runtime.

Three buckets:
- `yagye-lake-raw` — raw Bronze events (NDJSON), append-only, partitioned by hive `dt=YYYY-MM-DD`
- `yagye-lake-silver` — deduplicated, PII-hashed Parquet produced by DuckDB Silver ETL
- `yagye-lake-gold` — aggregated feature tables produced by DuckDB Gold ETL

Bronze S3 key format: `events/dt=YYYY-MM-DD/{event_prefix}_{microseconds}.ndjson`
Rejected envelopes (schema validation failures): `events/rejected/dt=YYYY-MM-DD/…`

### Ingestion: DataLakeIngestionWorker (Oban)

An Oban worker (`YagyeCore.DataLake.Workers.DataLakeIngestionWorker`) runs every
60 seconds and batch-writes pending outbox events to Bronze. Each NDJSON batch
contains the full event envelope (`event_id`, `event_type`, `event_version`,
`payload`, `mode`, `correlation_id`, etc.) as JSON Draft-07 objects. Envelopes
failing schema validation are written to the rejected prefix rather than dropped.

Schemas for the nine event families (`payment`, `settlement`, `dispute`,
`reconciliation`, `compliance`, `merchant`, `checkout_session`, `payment_link`,
`webhook`) live in `apps/yagye_core/priv/schema_registry/` and are registered
to Redpanda's schema registry via `mix yagye.schema_registry.register`.

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

### Synthetic data: yagye_simulator load generator

A `mix simulator.generate_load` Mix task fires parameterised payment batches
at Core via the API using deterministic MSISDN prefixes. This produces a
labeled dataset (success / decline / timeout / fraud-burst) for model training
before any real merchant traffic exists.

### Network placement

| Service | Docker network |
|---------|---------------|
| Floci | `data` (DB + Redpanda access) |
| DataLakeIngestionWorker (Oban, in yagye_core) | `core` |
| DuckDB ETL jobs (yagye_data Python) | `data` |
| ML scoring service (yagye_scoring) | `core_mesh` (Core must reach it; Portal must not) |

---

## Consequences

- The analytics path has zero read pressure on the Core write DB.
- Local development uses identical code paths as production — no separate
  "dev mode" for data pipelines.
- Parquet + DuckDB format is directly queryable by AWS Athena and Glue if
  the team ever needs a managed service — no migration required.
- Event schemas must be stable before ingestion is built. Breaking schema
  changes require a new partition prefix, not a migration.
