# Data Engineering Architecture

**Last updated:** 2026-10-21

This document describes Yagye's full data platform architecture: how operational
data is extracted from transactional databases, ingested into the lakehouse,
processed through a medallion pipeline, and made available for analytics, ML
training, and regulatory reporting. It is not a quickstart — it is the definitive
reference for every engineering decision in the data layer.

Read `docs/architecture/system-overview.md` and
`docs/architecture/engineering-concepts.md` first.

---

## Table of Contents

1. [Why a Separate Data Platform](#1-why-a-separate-data-platform)
2. [The OLTP / OLAP Boundary](#2-the-oltp--olap-boundary)
3. [Lakehouse Pattern and Why Not a Warehouse](#3-lakehouse-pattern-and-why-not-a-warehouse)
4. [Change Data Capture (CDC)](#4-change-data-capture-cdc)
5. [The Medallion Architecture: Bronze → Silver → Gold](#5-the-medallion-architecture-bronze--silver--gold)
6. [Storage Layout and Partitioning](#6-storage-layout-and-partitioning)
7. [Parquet: Why This Format](#7-parquet-why-this-format)
8. [DuckDB as the Query Engine](#8-duckdb-as-the-query-engine)
9. [Redpanda Connect: The Ingestion Pipeline](#9-redpanda-connect-the-ingestion-pipeline)
10. [Exactly-Once Ingestion Guarantees](#10-exactly-once-ingestion-guarantees)
11. [Schema Evolution and Compatibility](#11-schema-evolution-and-compatibility)
12. [Data Freshness SLAs](#12-data-freshness-slas)
13. [Feature Store and ML Integration](#13-feature-store-and-ml-integration)
14. [Regulatory Reporting Layer](#14-regulatory-reporting-layer)
15. [Floci: Local Development Emulation](#15-floci-local-development-emulation)
16. [Data Governance and Access Control](#16-data-governance-and-access-control)
17. [Lambda Architecture — What We Are](#17-lambda-architecture--what-we-are)
18. [Kimball Data Modeling — Fact and Dimension Tables](#18-kimball-data-modeling--fact-and-dimension-tables)
19. [Slowly Changing Dimensions (SCD)](#19-slowly-changing-dimensions-scd--a-critical-correctness-concern)
20. [Data Marts](#20-data-marts)
21. [Data Mesh vs Centralized Architecture](#21-data-mesh-vs-centralized-architecture)
22. [Orchestration — Oban Instead of Airflow/Dagster](#22-orchestration--oban-instead-of-airflowdagster)
23. [DBT vs Raw DuckDB SQL](#23-dbt-vs-raw-duckdb-sql)
24. [Data Lineage](#24-data-lineage)
25. [Pipeline Testing and Data Quality](#25-pipeline-testing-and-data-quality)
26. [AI Layer 1 — LLM Enrichment](#26-ai-layer-1--llm-enrichment)
27. [AI Layer 2 — RAG Chatbot on Analytics Data](#27-ai-layer-2--rag-chatbot-on-analytics-data)
28. [AI Layer 3 — Text-to-SQL for Merchants](#28-ai-layer-3--text-to-sql-for-merchants)
29. [Data Architecture Evolution and Where Yagye Sits](#29-data-architecture-evolution-and-where-yagye-sits)
30. [Data Maturity Levels](#30-data-maturity-levels)

**See also:** [`ai-layer.md`](ai-layer.md) — full detail on all three AI products (LLM enrichment,
ops RAG chatbot, merchant text-to-SQL), including architecture diagrams, security model, cost
governance, and failure modes.

---

## 1. Why a Separate Data Platform

### The fundamental mismatch

Yagye's operational databases (`core_db`, `portal_db`) are PostgreSQL instances
optimised for OLTP (Online Transaction Processing): high-concurrency, small
reads/writes, short transactions, row-level locking. They are deliberately
hostile to analytical workloads.

Consider a query: "Show me the total volume by provider for all live payments
in the last 6 months, grouped by merchant sector and day." On the operational
database, this query:

- Scans tens of millions of rows in `payments` and `ledger_postings`
- Holds read locks that compete with concurrent payment writes
- May take minutes — during which the payment API's query planner is disrupted
- Requires joining tables that are normalised for writes, not reads
- Exposes the production schema to data science tooling that should never touch it

On the data platform, the same query:
- Reads pre-partitioned Parquet files in columnar format
- Runs entirely in DuckDB (in-process, no network)
- Touches only the columns it needs (columnar skipping)
- Completes in seconds on a laptop
- Has no interaction with the operational databases whatsoever

This is not premature optimisation. It is a structural separation that protects
payment reliability from analytical query load — a non-negotiable requirement
for a PSP operating in a regulated market.

### What the data platform must enable

| Capability | Why essential for a PSP |
|---|---|
| ML training data | Historical labeled outcomes for routing, risk, reserve models |
| Regulatory reporting | BoG (Bank of Ghana) queries covering months of history |
| Revenue analytics | Daily P&L, provider cost analysis, fee revenue breakdown |
| Chargeback analytics | Dispute rates by merchant, network, amount range |
| Audit trail reconstruction | Immutable event history for investigations |
| Merchant business intelligence | Cohort analysis, retention, volume trends |
| Data science experimentation | Sandbox environment for model development |

---

## 2. The OLTP / OLAP Boundary

### Two fundamentally different access patterns

```
OLTP (operational)                  OLAP (analytical)
────────────────────                ─────────────────────
Many small, concurrent writes       Few large, serial reads
Row-level access (by ID)            Column-level access (aggregate)
Short transactions (< 100ms)        Long scans (seconds to minutes)
Normalised schema (3NF)             Denormalised schema (star/wide)
B-tree indexes on PKs and FKs       Column statistics, zone maps
Latest state only                   Historical time series
```

PostgreSQL excels at OLTP. It does not excel at OLAP — it is a row-oriented
storage engine. Reading a single column from 10 million rows requires scanning
all 10 million rows' worth of data from disk, even if the column is only 10%
of each row's width.

DuckDB on Parquet excels at OLAP. Parquet stores data column by column. Reading
the `amount` column from 10 million payments reads only the `amount` column —
one sequential scan of compressed integers, completed in milliseconds.

### Why not read replicas?

A PostgreSQL read replica solves the lock contention problem (analytical reads
don't compete with operational writes). But it does not solve:

- **Column-oriented performance.** A read replica is still row-oriented. An
  aggregation over 50 million rows is still slow.
- **Schema lock-in.** The read replica mirrors the normalised operational schema.
  Analytics needs denormalised, enriched, typed data.
- **ML training.** A training pipeline that reads directly from the replica
  creates an operational dependency on the production database. A slow training
  job creates read load on the replica, which receives the same WAL stream as
  production. They are not independent.
- **Regulatory immutability.** A read replica can be altered by a schema
  migration. The raw data lake is append-only and immutable by design — a
  regulatory requirement.

---

## 3. Lakehouse Pattern and Why Not a Warehouse

### What a lakehouse is

A lakehouse combines the durability and openness of a data lake with the
structure and queryability of a data warehouse, without a separate managed
warehouse service.

```
Traditional warehouse stack:         Yagye's lakehouse stack:
───────────────────────────           ────────────────────────
Operational DB                         Operational DB (PostgreSQL)
    │ ETL (nightly batch)                  │ CDC (Redpanda Connect, near-realtime)
    ▼                                      ▼
Data warehouse                         Object storage (Parquet on S3 / Floci)
(Snowflake, BigQuery, Redshift)            │ DuckDB (in-process query engine)
    │ query                                ▼
    ▼                                  Analytics results, feature tables,
BI / ML tools                          ML training datasets
```

### Why not Snowflake or BigQuery?

At Yagye's current scale (hundreds of thousands of payments per month, growing
to millions), a managed data warehouse is:

- **Overengineered.** Snowflake and BigQuery are designed for petabyte-scale
  concurrent analytics teams. Yagye has one data engineering function.
- **Expensive.** Warehouse compute costs at any serious query volume are
  significant. DuckDB on Parquet is essentially free (CPU + storage).
- **Vendor lock-in.** Parquet is an open, standardised format. Any future
  tool (Spark, Trino, Athena, DuckDB, Pandas, Polars) can read it without
  migration. Snowflake's internal format requires export.
- **Development friction.** Running Snowflake locally for development requires
  a paid account and a network connection. DuckDB + Floci runs entirely offline.

The lakehouse approach means:
1. Raw data in open format (Parquet) on open storage (S3).
2. Query engine is a process, not a service (DuckDB embedded).
3. No warehouse bill. No network hop for analytics.
4. Easy local development (Floci emulates S3 perfectly).

### The lakehouse is Bronze + Silver + Gold — not just Bronze

A common misread: "Bronze is the lakehouse." Bronze alone is a **data lake** —
raw, cheap, append-only, and unstructured. It is not directly queryable for
analytics: files are small (500 rows each), duplicates exist, PII is present,
and there is no pre-aggregation.

The **lakehouse** is the entire three-layer system:

```
Bronze (yagye-lake-raw/)    ← the "lake" part: raw, immutable, open
        ↓ DuckDB ETL
Silver (yagye-lake-silver/) ← validated, typed, deduplicated
        ↓ DuckDB ETL
Gold   (yagye-lake-gold/)   ← pre-aggregated, business-ready
        ↓ DuckDB queries
ML training / BI / Reports  ← the "house" part: structured, queryable
```

What makes it a *lakehouse* rather than just a data lake is that Silver and
Gold impose warehouse-like structure (typed schemas, star schema, SCD Type 2)
on top of lake-like storage (open Parquet files on S3). The query engine
(DuckDB) reads across all three layers without a separate warehouse service.

When Yagye reaches a scale where DuckDB's single-node performance is a
bottleneck (hundreds of analysts running concurrent complex queries), migrating
to Trino or AWS Athena is straightforward — they read the same Parquet files.

---

## 4. Change Data Capture (CDC)

### What CDC is and why it matters

Change Data Capture (CDC) is the process of detecting database changes and
delivering them to downstream systems as they happen — rather than as periodic
batch extracts. It is the foundation of Yagye's ingestion pipeline.

There are two main mechanisms for CDC. The first reads changes from the
database's write-ahead log (WAL), making it transparent to application code —
tools like Debezium work this way. The second is the **transactional outbox**:
the application explicitly writes an event row in the same database transaction
as the state change it is recording. Yagye uses the outbox approach, not WAL.

**Why this distinction matters:** WAL-based CDC captures every column change
on every row in every table — it is a generic row-level diff of the database.
Outbox-as-CDC captures only the events the application explicitly emits, with
a curated, domain-meaningful payload. The two approaches produce very different
data at the destination — see §4's CDC section for the comparison.

**Alternative: bulk export (nightly batch):**

```
Nightly at 3AM:
  SELECT * FROM payments WHERE updated_at > yesterday
  → write to S3
```

Problems:
- Data is up to 24 hours stale.
- `updated_at` does not capture deletes.
- Reprocessing all "changed" rows every night is expensive.
- A payment that changed state 10 times in one day looks like one change.
- Missing events: the intermediate states are lost.

**CDC captures everything:**

```
10:05:23 — INSERT payments (state='created')       → Bronze event
10:05:24 — UPDATE payments (state='dispatched')    → Bronze event
10:05:55 — UPDATE payments (state='succeeded')     → Bronze event
```

Every state transition is a separate event in the Bronze layer.
The full history is preserved.

### Yagye's CDC approach: Outbox + Redpanda Connect

Yagye does NOT use PostgreSQL logical replication (WAL-based CDC tools like
Debezium) for the primary pipeline. The reason: the outbox is already CDC.

The transactional outbox (§6 in engineering-concepts.md) writes an explicit
event row for every significant state change, in the same transaction as the
state change. This is intentional, domain-modelled CDC — not a generic WAL
diff extraction.

Benefits of outbox-as-CDC over WAL-based CDC:
- Events carry semantic meaning (payment.succeeded), not row-level diffs
- The schema is stable (an event schema is versioned; a WAL diff is not)
- Sensitive columns are never emitted (the event payload is curated, not a full row dump)
- No dependency on PostgreSQL's logical replication slot (which can block vacuuming)

### The data lake is an event journal, not a database replica

This is a critical distinction. **Not every database table has data in the
Bronze layer.** Only domain events that pass through the outbox do. Tables like
`fee_records`, `ledger_postings`, `users`, `api_keys`, `roles`, `pricing_rules`,
and `processed_events` are never in the lake — no event is emitted for them.
If analytical data from those tables is needed, it must be included in an
event's payload at the point of emission.

WAL-based CDC tools like Debezium would give you a row-level diff for every
table automatically. The outbox approach gives you semantic events for the
domains you instrument. The benefit is a curated, meaningful event stream. The
responsibility is making sure every event carries the payload fields downstream
analytics actually needs.

### Event catalogue: what enters the Bronze layer

The following domain events are currently emitted to the outbox and flow into
the Bronze layer. This table is the authoritative list — if an event type is
not here, it is not in the lake.

| Domain | Event types |
|---|---|
| Payments | `payment.created`, `payment.processing`, `payment.authorised`, `payment.succeeded`, `payment.failed`, `payment.refunded`, `payment.requires_action`, `payment.indeterminate` |
| Settlement | `settlement.batch.created`, `settlement.batch.awaiting_approval`, `settlement.batch.dispatch_approved`, `settlement.batch.dispatch_rejected`, `settlement.batch.dispatched`, `settlement.batch.settled` |
| Disputes | `dispute.resolved` |
| Reconciliation | `reconciliation.run.completed`, `reconciliation.report.ingested`, `reconciliation.adjustment.proposed`, `reconciliation.adjustment.approved`, `reconciliation.adjustment.rejected` |
| Compliance / KYB | `compliance.onboarding_submitted`, `compliance.beneficial_owner_added`, `compliance.beneficial_owner_updated`, `compliance.beneficial_owner_removed`, `compliance.kyb_document_uploaded`, `compliance.screening_hit_raised`, `compliance.screening_hit_dispositioned` |
| Merchants | `merchant.registered`, `merchant.approved`, `merchant.sandbox_enabled`, `merchant.application.resubmitted` |
| Checkout | `checkout_session.completed` |
| Payment Links | `payment_link.created`, `payment_link.deactivated` |
| Webhooks | `webhook.delivery.attempted` |

Reference data (current merchant profiles, provider configurations) does not
travel as events — it is periodically snapshotted into Silver as static Parquet
files (`merchants_latest.parquet`, `providers_latest.parquet`) and joined in
at ETL time.

**Adding a new domain to the lake** means two things: (1) emit an outbox event
from the application at the right state transition, and (2) write a Silver ETL
script to transform that Bronze event into a typed Silver table.

The outbox feeds Redpanda (at P14). Redpanda Connect (the streaming ETL layer)
consumes from Redpanda topics and writes to the Bronze layer.

### Pre-P14: direct Oban relay to S3

Before Redpanda (P14), the outbox relay writes events to S3 via an Oban worker:

```
outbox_messages (unprocessed)
    │ OutboxRelayWorker polls every ~1s
    ▼
Oban: DataLakeIngestionWorker
    │ Batches events in memory (max 100, max 30s window)
    ▼
S3/Floci: Bronze Parquet files (batch write via ExParquet)
```

### At P14: Redpanda Connect as the ETL layer

```
outbox_messages → OutboxRelayWorker → Redpanda topic "payment.events"
                                            │
                    Redpanda Connect pipeline (declarative YAML config)
                                            │
                    ┌───────────────────────▼────────────────────────┐
                    │  Redpanda Connect: S3 Sink connector            │
                    │                                                 │
                    │  input:  redpanda_consumer (payment.events)     │
                    │  buffer: batch 500 records OR 30s               │
                    │  output: s3 (Parquet format)                    │
                    │          key: year={}/month={}/day={}/hour={}   │
                    │          schema: Apache Arrow schema from event  │
                    └─────────────────────────────────────────────────┘
                                            │
                    ┌───────────────────────▼────────────────────────┐
                    │  Bronze Layer (S3/Floci)                        │
                    │  yagye-lake-raw/                               │
                    │    payment.succeeded/year=2026/month=10/...    │
                    └─────────────────────────────────────────────────┘
```

Redpanda Connect is a single binary that is configured via YAML. No JVM,
no Kafka Streams, no Flink. It handles:
- Consumer group management (offset commits)
- Batching and buffering
- S3 multipart upload
- Schema application (Parquet column types from Arrow schema)
- Dead-letter routing for malformed events

---

## 5. The Medallion Architecture: Bronze → Silver → Gold

The medallion architecture is the industry standard for data lake organisation.
Data flows from raw (Bronze) through validated/enriched (Silver) to business-ready
(Gold). Each layer has a specific contract, specific consumers, and specific
quality guarantees.

```
PostgreSQL (core_db)
    │ CDC via outbox + Redpanda Connect
    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  BRONZE LAYER  (yagye-lake-raw/)                                             │
│  "Raw, immutable events — exactly as emitted from the outbox"               │
│                                                                             │
│  Properties:                                                                │
│  ✓ Append-only. Files are never modified after write.                       │
│  ✓ Partitioned by event date (year/month/day/hour)                          │
│  ✓ All event types in separate prefixes                                     │
│  ✓ Schema matches the outbox EventEnvelope exactly                          │
│  ✗ May contain nulls, inconsistent types, duplicate deliveries              │
│  ✗ Not queryable efficiently (not pre-aggregated or denormalised)           │
│                                                                             │
│  Files: batch_20261018T120000Z.parquet (raw events, 500 rows per file)      │
└──────────────────────────────────────────────────────────────────────────────┘
                      │ DuckDB ETL (runs hourly)
                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  SILVER LAYER  (yagye-lake-silver/)                                          │
│  "Validated, deduplicated, typed, joined to reference data"                 │
│                                                                             │
│  Properties:                                                                │
│  ✓ Deduplicated (event_id unique — same event_id from duplicate delivery    │
│    appears once)                                                            │
│  ✓ All timestamps normalised to UTC                                         │
│  ✓ Amounts validated as positive integers                                   │
│  ✓ Merchant and provider names joined from reference tables                 │
│  ✓ Mode column validated (simulation / sandbox / live)                      │
│  ✓ Partitioned by effective_date (domain date for correct period queries)   │
│  ✓ Schema contracts versioned with forward-compatible evolution rules       │
│                                                                             │
│  Files: payments_silver/effective_date=2026-10-18/part-001.parquet          │
└──────────────────────────────────────────────────────────────────────────────┘
                      │ DuckDB ETL (runs nightly + on-demand)
                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  GOLD LAYER  (yagye-lake-gold/)                                              │
│  "Business-ready: pre-aggregated metrics, feature tables, report datasets"  │
│                                                                             │
│  Properties:                                                                │
│  ✓ Aggregated and denormalised for specific use cases                       │
│  ✓ Pre-computed: queries against Gold should complete in seconds            │
│  ✓ Mode = 'live' only (no simulation or sandbox data in analytics tables)  │
│  ✓ Named for the consumer: payments_daily, provider_health_hourly,          │
│     merchant_features_weekly, risk_features_hourly                         │
│  ✓ PII fields hashed or removed (MSISDN → hashed; name → removed)          │
│                                                                             │
│  Files: merchant_features_weekly/week=2026-W42/part-001.parquet             │
│         provider_health_hourly/date=2026-10-18/hour=12/part-001.parquet     │
└──────────────────────────────────────────────────────────────────────────────┘
                      │
         ┌────────────┼────────────────────┐
         ▼            ▼                    ▼
    ML Training    Regulatory          BI Dashboards
    Datasets       Reports             (Grafana / ECharts)
```

### Bronze: raw and immutable

Bronze files are written once and never modified. The directory name encodes
partition values:

```
yagye-lake-raw/
  payment.succeeded/
    year=2026/month=10/day=18/hour=12/
      batch_20261018T120523Z_0001.parquet   ← 500 events
      batch_20261018T121004Z_0002.parquet   ← 500 events
  payment.failed/
    ...
  settlement.batch.dispatched/
    ...
  merchant.approved/
    ...
  compliance.screening_hit_raised/
    ...
```
(Event type names map directly to S3 prefix names — see the event catalogue
in §4 for the full list.)

The partition key is the **ingestion timestamp** (when the event was written to
S3), not the event's `effective_at` timestamp. This is intentional: late-arriving
events (from reconciliation) are written to the Bronze partition of when they
arrived, not when they occurred. Silver handles the domain date re-sorting.

### Silver: validated and enriched

The Silver ETL reads from Bronze and produces validated, deduplicated, typed data.
Key transformations:

```sql
-- DuckDB SQL (Silver ETL for payment.succeeded events)
INSERT OR IGNORE INTO silver_payments
SELECT
  event_id,                                      -- dedup key
  aggregate_id AS core_payment_id,
  CAST(envelope->>'effective_at' AS TIMESTAMPTZ) AS effective_at,
  CAST(envelope->>'recorded_at' AS TIMESTAMPTZ)  AS recorded_at,
  CAST(envelope->>'amount' AS BIGINT)            AS amount_minor,
  envelope->>'currency'                          AS currency,
  envelope->>'mode'                              AS mode,
  -- JOIN reference data (read from S3 Parquet reference tables)
  m.business_name                                AS merchant_name,
  m.sector                                       AS merchant_sector,
  pr.display_name                                AS provider_name,
  -- Hash PII
  SHA256(envelope->>'customer_msisdn')           AS customer_msisdn_hash,
  DATE(CAST(envelope->>'effective_at' AS DATE))  AS effective_date
FROM read_parquet('s3://yagye-lake-raw/payment.succeeded/**/*.parquet')
  AS raw
LEFT JOIN read_parquet('s3://yagye-lake-silver/merchants/*.parquet')
  AS m ON m.merchant_id = raw.envelope->>'merchant_id'
LEFT JOIN read_parquet('s3://yagye-lake-silver/providers/*.parquet')
  AS pr ON pr.provider_code = raw.envelope->>'provider_code'
WHERE raw.inserted_at >= $last_watermark;
```

`INSERT OR IGNORE` (DuckDB's upsert equivalent with `ON CONFLICT DO NOTHING`
on `event_id`) provides deduplication. The same Bronze event arriving twice
from Redpanda's at-least-once delivery is silently collapsed.

### Gold: business-ready and pre-aggregated

Gold tables are built for specific query patterns. Each table answers one or
more business questions efficiently:

**`provider_health_hourly`** — answers: "Is a provider degraded right now?"
```
columns: provider_code, hour, attempt_count, success_count,
         success_rate, p50_latency_ms, p95_latency_ms, p99_latency_ms
consumer: routing predictor (ML features), ops Grafana dashboard
freshness: 5 minutes (rebuilt from Silver on every hourly run)
```

**`merchant_features_weekly`** — answers: "What is this merchant's risk profile?"
```
columns: merchant_id, week, volume_ghs, chargeback_rate,
         avg_payment_amount, network_mix, sector
consumer: risk scorer (ML features), reserve recommender
freshness: 24 hours (rebuilt from Silver nightly)
```

**`payments_daily`** — answers: "What was our payment volume and revenue today?"
```
columns: date, mode, currency, provider_code, merchant_sector,
         payment_count, gross_volume, platform_fees, net_volume
consumer: BI dashboards, regulatory reports
freshness: 6 hours (rebuilt from Silver 4x per day)
```

**`risk_features_hourly`** — answers: "What is this customer's risk profile right now?"
```
columns: customer_msisdn_hash, hour, attempt_count_1h, fail_count_1h,
         distinct_merchants_1h, amount_total_1h, is_velocity_breach
consumer: risk scorer (real-time features)
freshness: 1 hour
```

---

## 6. Storage Layout and Partitioning

### Object storage structure

```
s3://yagye-lake-raw/                           (Bronze)
  {event_type}/
    year={YYYY}/month={MM}/day={DD}/hour={HH}/
      batch_{timestamp}_{sequence}.parquet

s3://yagye-lake-silver/                        (Silver)
  payments/
    effective_date={YYYY-MM-DD}/
      part-{N:04d}.parquet
  providers/                                   (reference data)
    providers_latest.parquet
  merchants/                                   (reference data)
    merchants_latest.parquet

s3://yagye-lake-gold/                          (Gold)
  provider_health_hourly/
    date={YYYY-MM-DD}/hour={HH}/
      part-0001.parquet
  merchant_features_weekly/
    week={YYYY-W{WW}}/
      part-0001.parquet
  payments_daily/
    date={YYYY-MM-DD}/
      part-0001.parquet
  risk_features_hourly/
    date={YYYY-MM-DD}/hour={HH}/
      part-0001.parquet
  ml_training/
    routing_predictor/
      snapshot_{YYYY-MM-DD}.parquet
    risk_scorer/
      snapshot_{YYYY-MM-DD}.parquet
```

### Partition pruning

DuckDB performs partition pruning automatically when reading partitioned Parquet:

```sql
-- This query only reads the October 18 partition, not the entire lake
SELECT * FROM read_parquet('s3://yagye-lake-silver/payments/**/*.parquet')
WHERE effective_date = '2026-10-18';
-- → reads only s3://yagye-lake-silver/payments/effective_date=2026-10-18/*.parquet
```

Without Hive-style partitioned directories, the query above would scan all
Parquet files to find matching rows. With partitioning, DuckDB reads the
directory listing, identifies matching partitions, and reads only those files.

For time-series data (most of Yagye's data), date partitioning reduces query
scope by orders of magnitude. A 30-day query reads only 30 partitions instead
of the entire dataset.

### File sizing: the 100MB–500MB sweet spot

Each Parquet file in the Silver and Gold layers is targeted at 100–500 MB
uncompressed. This is the sweet spot because:

- **Too small (< 10 MB):** Object storage overhead per file dominates. S3 has
  a minimum billing unit of 128 KB and a metadata overhead per object. Millions
  of tiny files slow directory listings and partition pruning.
- **Too large (> 1 GB):** Row groups within the file can't be pruned by predicate
  pushdown. Also, a single failed write wastes more work.

The batch sizing in the Bronze layer (500 events ≈ 1–5 MB) is fine for raw
ingestion because files accumulate within partitions. Silver ETL compacts them
into the 100–500 MB target.

---

## 7. Parquet: Why This Format

### Why not CSV or JSON?

| Format | Read speed | Storage size | Schema | Columnar | Splittable |
|---|---|---|---|---|---|
| CSV | Slow (text parsing) | Large | None | No | Yes (by line) |
| JSON Lines | Very slow | Very large | None | No | Yes (by line) |
| Parquet | Very fast | Small | Embedded | Yes | Yes (by row group) |
| ORC | Fast | Small | Embedded | Yes | Yes |

Parquet stores data in column chunks. A query reading only `amount` and `currency`
from 10 million rows reads only those two columns from disk — the other 20+ columns
are never loaded. For analytical workloads that aggregate few columns across many
rows, this is a 10–50× speed improvement over row-oriented formats.

### Why not ORC?

ORC is also columnar and efficient. Parquet is preferred because:
- DuckDB's native Parquet support is more mature and faster than its ORC support
- The broader ecosystem (Pandas, Polars, Spark, Athena, BigQuery external tables)
  all prefer Parquet
- Apache Arrow (in-memory columnar format) converts to/from Parquet natively —
  DuckDB uses Arrow internally, so there is zero copy overhead

### Compression

Bronze files use Snappy compression (fast, moderate ratio — good for write-heavy
ingestion). Silver and Gold files use Zstd compression (slower to write, better
ratio — good for read-heavy analytics). Typical ratios:

- Snappy on payment events: ~3–5× compression
- Zstd level 3 on Silver payments: ~6–8× compression

A million payment events in JSON: ~500 MB. In Parquet Zstd: ~30 MB. This is
relevant for cost (S3 storage and transfer pricing) and for query speed (less
data to read from object storage).

---

## 8. DuckDB as the Query Engine

### What DuckDB is

DuckDB is an in-process analytical SQL database. Unlike PostgreSQL or MySQL,
it has no server process — it runs as a library within the application process.
It is to analytical SQL what SQLite is to transactional SQL.

Key properties relevant to Yagye:
- Reads Parquet directly from S3 without a staging copy
- Fully SQL-compatible (window functions, CTEs, lateral joins, PIVOT)
- Columnar execution engine — `SUM(amount)` on 10M rows runs in milliseconds
- Parallel execution (uses multiple CPU cores automatically)
- No server to manage — runs in any Python or Elixir/Rust environment
- Apache Arrow native — integrates with Pandas and Polars without copy

### How DuckDB is used in Yagye

**Silver ETL jobs** (Python, runs hourly):

```python
import duckdb

con = duckdb.connect()
con.execute("""
  INSTALL httpfs; LOAD httpfs;
  SET s3_endpoint = 'floci:9000';  -- Floci in dev, AWS S3 in prod
  SET s3_access_key_id = ...;

  INSERT INTO silver_payments
  SELECT ...
  FROM read_parquet('s3://yagye-lake-raw/payment.succeeded/**/*.parquet')
  WHERE ...
""")
```

**Gold ETL jobs** (Python, runs on schedule):

```python
con.execute("""
  COPY (
    SELECT
      provider_code,
      DATE_TRUNC('hour', effective_at) AS hour,
      COUNT(*) AS attempt_count,
      SUM(CASE WHEN status = 'succeeded' THEN 1 ELSE 0 END) AS success_count,
      AVG(latency_ms) AS avg_latency_ms,
      QUANTILE_CONT(latency_ms, 0.95) AS p95_latency_ms
    FROM read_parquet('s3://yagye-lake-silver/payments/**/*.parquet')
    WHERE effective_date >= CURRENT_DATE - 2  -- lookback for late arrivals
      AND mode = 'live'
    GROUP BY 1, 2
  ) TO 's3://yagye-lake-gold/provider_health_hourly/date={today}/hour={hour}/part-0001.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
""")
```

**ML training dataset export** (Python, runs weekly):

```python
con.execute("""
  COPY (
    SELECT
      p.provider_code,
      p.network_code,
      p.amount_minor,
      FLOOR(p.amount_minor / 10000.0) AS amount_bucket,
      EXTRACT(HOUR FROM p.effective_at) AS hour_of_day,
      EXTRACT(DOW  FROM p.effective_at) AS day_of_week,
      ph.success_rate_1h AS recent_success_rate_1h,
      ph.p95_latency_ms  AS avg_latency_ms_1h,
      CASE WHEN p.status = 'succeeded' THEN 1 ELSE 0 END AS label
    FROM read_parquet('s3://yagye-lake-silver/payments/**/*.parquet') p
    JOIN read_parquet('s3://yagye-lake-gold/provider_health_hourly/**/*.parquet') ph
      ON ph.provider_code = p.provider_code
      AND ph.hour = DATE_TRUNC('hour', p.effective_at)
    WHERE p.effective_date BETWEEN CURRENT_DATE - 90 AND CURRENT_DATE - 1
      AND p.mode = 'live'
  ) TO 's3://yagye-lake-gold/ml_training/routing_predictor/snapshot_{today}.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
""")
```

### Why not Spark?

Apache Spark is the dominant big data processing framework. It is not the right
choice for Yagye at current scale because:

- **Operational complexity.** Spark requires a cluster (master + workers),
  cluster manager (YARN, Kubernetes, or Databricks), and Java/Scala toolchain.
  DuckDB requires nothing — it is a Python `pip install`.
- **Latency.** Spark jobs have significant startup overhead (JVM spin-up,
  cluster task scheduling). DuckDB starts in milliseconds. An hourly ETL
  job running for 30 seconds in DuckDB would run for 5 minutes in Spark.
- **Scale mismatch.** Spark's distributed execution pays off at terabyte scale.
  Yagye's Silver layer at steady state is tens of gigabytes — trivially within
  DuckDB's single-node capacity.
- **Cost.** A Databricks cluster running 24/7 costs thousands per month.
  DuckDB runs on the same instance as the ETL orchestration.

Migration path: when Yagye reaches multi-terabyte scale, replace DuckDB with
Trino (distributed SQL over Parquet) or AWS Athena. The Parquet files are
unchanged — only the query engine changes.

---

## 9. Redpanda Connect: The Ingestion Pipeline

### What Redpanda Connect is

Redpanda Connect (formerly Benthos) is a declarative stream processing framework.
It reads from sources (Redpanda topics, HTTP endpoints, S3 buckets), applies
transformations (field mapping, filtering, JSON parsing, schema validation),
and writes to sinks (S3, databases, HTTP endpoints).

It is a single binary, configured entirely via YAML, with no JVM dependency and
minimal operational overhead. Each pipeline is a YAML file that Redpanda Connect
executes.

### The payment events ingestion pipeline

```yaml
# pipelines/payment-events-to-bronze.yaml
input:
  kafka:
    addresses: ["redpanda:9092"]
    topics: ["payment.events", "merchant.events", "settlement.events"]
    consumer_group: data-lake-ingestion
    start_from_oldest: false

pipeline:
  threads: 4
  processors:
    # Parse the event envelope
    - mapping: |
        root = this
        root.ingested_at = now()
        root.source_partition = meta("kafka_partition")
        root.source_offset = meta("kafka_offset")

    # Route by event_type to separate S3 prefixes
    - switch:
        - check: root.event_type == "payment.succeeded"
          processors:
            - mapping: root.s3_prefix = "payment.succeeded"
        - check: root.event_type == "payment.failed"
          processors:
            - mapping: root.s3_prefix = "payment.failed"
        - default:
          processors:
            - mapping: root.s3_prefix = root.event_type

output:
  aws_s3:
    bucket: yagye-lake-raw
    path: '${! this.s3_prefix }/year=${! this.effective_at.ts_format("2006") }/month=${! this.effective_at.ts_format("01") }/day=${! this.effective_at.ts_format("02") }/hour=${! this.effective_at.ts_format("15") }/batch_${! now().ts_format("20060102T150405Z") }_${! count("batch") }.parquet'
    format: parquet
    schema:
      - name: event_id
        type: string
      - name: event_type
        type: string
      - name: aggregate_id
        type: string
      - name: aggregate_version
        type: int32
      - name: effective_at
        type: timestamp[us]
      - name: envelope
        type: string  # JSON string — typed in Silver ETL
      - name: ingested_at
        type: timestamp[us]
    batching:
      count: 500         # max 500 rows per file
      period: "30s"      # flush after 30s even if < 500 rows
      byte_size: 10485760  # flush if batch > 10MB
```

### Dead-letter handling in the pipeline

Events that fail schema validation or Parquet serialisation are routed to a
dead-letter S3 prefix:

```yaml
output:
  fallback:
    - aws_s3:
        bucket: yagye-lake-raw
        path: '${! this.s3_prefix }/...'
        # ... primary output
    - aws_s3:
        bucket: yagye-lake-dlq  # dead-letter
        path: 'dlq/${! this.s3_prefix }/${! now().ts_format("20060102T150405Z") }.json'
```

Dead-letter events are JSON (not Parquet) so they can be inspected without a
query engine. A daily alert fires when `yagye-lake-dlq` has new objects. Each
dead-letter event includes the original payload and the error message, allowing
schema issues to be diagnosed and the Bronze ETL to be corrected and replayed.

---

## 10. Exactly-Once Ingestion Guarantees

### The at-least-once problem

Redpanda (Kafka-compatible) guarantees at-least-once delivery. After a consumer
commits an offset, the broker considers the message delivered. If the consumer
crashes after processing but before committing the offset, the message is
redelivered. The Bronze layer may receive the same event twice.

This is acceptable in Bronze (the raw layer exists to capture everything). But
Silver must deduplicate before writing Gold tables, and Gold tables must not
double-count payment volumes.

### Deduplication in Silver ETL

```python
# Silver ETL: INSERT with deduplication on event_id
con.execute("""
  INSERT INTO silver_payments
  SELECT DISTINCT ON (event_id) *
  FROM new_rows
  WHERE event_id NOT IN (
    SELECT event_id FROM silver_payments
  )
""")
```

The `event_id` (ULID from the outbox) is the deduplication key. A ULID that
appears twice in the Bronze layer produces one Silver row. This is the same
strategy as the `processed_events` table in the portal (§7 of engineering-concepts.md)
— idempotent INSERT on a unique key.

### Watermark-based incremental processing

The Silver ETL maintains a watermark table that tracks the last processed
Bronze timestamp:

```
watermarks
  layer        text   -- 'silver', 'gold'
  table_name   text   -- 'payments', 'provider_health_hourly'
  watermark_ts timestamptz
```

Each ETL run:
1. Reads `watermark_ts` for this table.
2. Reads Bronze files with `ingested_at > watermark_ts`.
3. Processes and writes to Silver.
4. Updates `watermark_ts = MAX(ingested_at)` from the processed batch.

This ensures each Bronze file is processed exactly once in normal operation.
On failure (process crash after write, before watermark update), the Bronze
files are reprocessed — Silver deduplication handles the duplicates.

### Late arrivals

Late-arriving events (a reconciliation confirms a payment from 3 days ago) land
in the Bronze partition of their ingestion date. The Silver ETL uses a
configurable lookback window:

```python
# Silver ETL processes Bronze files from the last 7 days on every run
# (not just yesterday's) to catch late arrivals
WHERE ingested_at >= NOW() - INTERVAL '7 days'
```

Gold tables that must be correct for past dates (e.g. regulatory reports) are
rebuilt from Silver after the lookback window closes. The ETL job system tracks
which Gold partitions need rebuilding when Silver receives late arrivals.

---

## 11. Schema Evolution and Compatibility

### The event schema is the contract

Every domain event in Yagye's outbox has an explicit schema. Schema changes
follow a strict compatibility policy:

**Backward-compatible (allowed without version bump):**
- Adding a new optional field with a default value
- Adding a new event type (new topic)

**Breaking (requires a new schema version):**
- Removing a field
- Changing a field's type
- Renaming a field

When a breaking change is needed:
1. The new event schema is published as `schema_version: 2`.
2. Both versions are written to the outbox for a dual-write period.
3. The Bronze ETL handles both schema versions (the `envelope` JSON is flexible).
4. The Silver ETL reads both and maps to the unified Silver schema.
5. After 30 days, the old schema is deprecated.

This is forward-compatible schema evolution: the Bronze layer is preserved as
raw JSON in the `envelope` column, so new fields added later can be read by
re-running the Silver ETL against the old Bronze data.

### Arrow schema for Parquet files

Every Parquet file uses an explicit Apache Arrow schema registered in the schema
registry. The schema registry is a simple directory of JSON schema files:

```
schemas/
  bronze/
    payment.succeeded.v1.json
    payment.succeeded.v2.json
  silver/
    payments.v1.json
  gold/
    provider_health_hourly.v1.json
```

The Redpanda Connect pipeline reads the schema version from the event envelope
and applies the correct Arrow schema when writing Parquet. DuckDB reads the
embedded Parquet schema when querying — no external registry needed at query time.

---

## 12. Data Freshness SLAs

Each layer has a documented freshness SLA:

| Layer | Table | Freshness | Rebuild cadence |
|---|---|---|---|
| Bronze | All events | 30 seconds | Streaming (Redpanda Connect) |
| Silver | payments | 1 hour | Hourly cron |
| Silver | merchants, providers | 24 hours | Nightly cron |
| Gold | provider_health_hourly | 5 minutes | Every 5 min cron |
| Gold | risk_features_hourly | 1 hour | Hourly cron |
| Gold | payments_daily | 6 hours | 4x daily cron |
| Gold | merchant_features_weekly | 24 hours | Nightly cron |
| ML training | routing_predictor snapshot | 7 days | Weekly cron |
| ML training | risk_scorer snapshot | 7 days | Weekly cron |

Freshness breaches trigger Grafana alerts:
- `provider_health_hourly` > 10 min stale → ops alert (routing decisions degrade)
- `payments_daily` > 12 hours stale → data engineering alert
- ML training snapshot > 14 days stale → ML team alert

### Circuit breaker for ML features

If the `provider_health_hourly` Gold table is stale (beyond SLA), the routing
predictor's feature fetch returns `null` for real-time features. The model
falls back to a static feature set (average success rates from the weekly
snapshot). This degraded mode is logged and alerted. Routing continues —
it just uses less fresh features.

---

## 13. Feature Store and ML Integration

### What a feature store is

A feature store is a system that manages ML features — the computed inputs that
models consume at both training time and inference time. Without a feature store,
teams recompute the same features multiple times in different places (training
script, serving layer, backtesting framework), leading to training-serving skew:
the feature computed at training time differs from the feature computed at
inference time, causing model accuracy degradation in production.

Yagye's feature store is lightweight: Gold layer Parquet files serve as the
training-time feature store (read by weekly training jobs), and a Redis cache
serves as the serving-time feature store (populated from Gold, read by the
FastAPI scoring service within SLA).

### Training-time features (from Gold Parquet)

```python
# Training pipeline reads from Gold Parquet
routing_features = con.execute("""
  SELECT
    p.payment_id,
    p.provider_code,
    p.network_code,
    p.amount_bucket,
    p.hour_of_day,
    p.day_of_week,
    ph.success_rate_1h,
    ph.success_rate_24h,
    ph.p95_latency_ms AS avg_latency_ms_1h,
    CASE WHEN p.status = 'succeeded' THEN 1 ELSE 0 END AS label
  FROM read_parquet('s3://yagye-lake-silver/payments/**/*.parquet') p
  JOIN read_parquet('s3://yagye-lake-gold/provider_health_hourly/**/*.parquet') ph
    ON ph.provider_code = p.provider_code
    AND ph.hour = DATE_TRUNC('hour', p.effective_at)
  WHERE p.effective_date BETWEEN CURRENT_DATE - 90 AND CURRENT_DATE - 1
    AND p.mode = 'live'
""").df()
```

### Serving-time features (from Redis cache)

```python
# FastAPI scoring service (inference time)
def get_features(provider_code: str, hour: int) -> dict:
    cached = redis.hgetall(f"features:provider:{provider_code}:h{hour}")
    if cached:
        return {k: float(v) for k, v in cached.items()}
    # Fallback: query Gold Parquet directly (slower but correct)
    return query_gold_parquet(provider_code, hour)
```

The Redis cache is populated by the Gold ETL job every 5 minutes:
```python
# After writing provider_health_hourly Parquet:
for row in provider_health_data:
    redis.hmset(f"features:provider:{row.provider_code}:h{row.hour}", {
        "success_rate_1h": row.success_rate,
        "p95_latency_ms": row.p95_latency_ms
    })
    redis.expire(f"features:provider:{row.provider_code}:h{row.hour}", 3600)
```

### Beyond the four P20 models

The four models above (routing predictor, risk scorer, reserve recommender,
churn predictor) are the P20 foundation. `ml-architecture.md` §15 documents
seven additional ML opportunities planned for P22+, in priority order:

1. **Smart retry prediction** — classify MoMo failure modes and predict optimal
   retry timing. Highest conversion rate impact given MoMo's diverse failure
   modes.
2. **Volume forecasting** — predict daily/weekly payment volume for treasury
   and float management. Fully buildable from existing Gold data.
3. **AML transaction monitoring** — detect structuring, velocity layering, and
   round-tripping patterns. Required for BOG STR compliance at scale.
4. **Network health forecasting** — predict MoMo network degradation before it
   starts, feeding the routing predictor as a forward-looking signal.
5. **Cross-merchant MSISDN fraud signal** — aggregate risk features across all
   merchants to catch fraud rings that stay below per-merchant velocity limits.
6. **KYB risk scoring** — automate low-risk merchant onboarding approvals to
   reduce compliance review bottleneck at scale.
7. **Settlement anomaly detection** — detect systematic provider under-reporting
   across settlement batches using unsupervised methods.

---

## 14. Regulatory Reporting Layer

### Bank of Ghana reporting requirements

Yagye operates as a payment service provider under the Bank of Ghana's
regulatory framework. Periodic reporting requirements include:

- Monthly transaction volume by payment type and currency
- Suspicious transaction reports (STRs) when transaction patterns trigger AML rules
- Annual financial statements with full payment and settlement data
- 7-year data retention for all financial records

The regulatory reporting layer is built on top of the Gold layer:

```python
# Monthly BoG report generation
con.execute("""
  COPY (
    SELECT
      DATE_TRUNC('month', effective_date) AS period,
      payment_method_type,
      currency,
      COUNT(*) AS transaction_count,
      SUM(amount_minor) / 100.0 AS gross_volume_ghs,
      SUM(fee_amount_minor) / 100.0 AS fee_revenue_ghs
    FROM read_parquet('s3://yagye-lake-silver/payments/**/*.parquet')
    WHERE effective_date BETWEEN '2026-10-01' AND '2026-10-31'
      AND mode = 'live'
    GROUP BY 1, 2, 3
    ORDER BY 1, 2, 3
  ) TO 'reports/bog_monthly_2026_10.csv' (FORMAT CSV, HEADER)
""")
```

### 7-year retention policy

The Bronze layer is the regulatory archive. S3 bucket lifecycle rules are
configured to:
- Transition to S3 Infrequent Access after 90 days (4× cheaper storage)
- Transition to S3 Glacier Instant Retrieval after 365 days (10× cheaper)
- Never expire (regulatory retention indefinite; review at 7 years)

S3 Object Lock (WORM — Write Once Read Many) is enabled on the Bronze bucket.
Once written, files cannot be deleted or overwritten even by an admin with
full S3 permissions. This satisfies the immutability requirement for regulatory
archives.

---

## 15. Floci: Local Development Emulation

### What Floci is

Floci is a local AWS S3 emulator. It speaks the same S3 API as real AWS S3,
which means all code that reads/writes S3 works identically in development
(Floci) and production (real S3) — no environment-specific branches.

```
Production:                         Development / CI:
  AWS S3                              Floci (runs as Docker container)
  s3://yagye-lake-raw/...             s3://yagye-lake-raw/...
  AWS credentials                     Floci credentials (any value)
  Real billing                        No billing
```

The S3 endpoint URL is the only configuration difference:

```python
# production
s3_endpoint = "https://s3.amazonaws.com"

# development
s3_endpoint = "http://floci:9000"
```

### Development workflow

```bash
# Start Floci
docker run -p 9000:9000 ghcr.io/floci-io/floci:latest

# Create buckets
aws --endpoint-url http://localhost:9000 s3 mb s3://yagye-lake-raw
aws --endpoint-url http://localhost:9000 s3 mb s3://yagye-lake-silver
aws --endpoint-url http://localhost:9000 s3 mb s3://yagye-lake-gold

# Run Silver ETL (DuckDB reads from Floci)
python scripts/etl/silver_payments.py --env=dev

# Query results
duckdb -c "SELECT COUNT(*) FROM read_parquet('s3://yagye-lake-silver/payments/**/*.parquet')"
```

Floci persists data to a local volume — the data lake survives container restarts.
For a clean slate in CI, the container is restarted with an empty volume.

### Synthetic data generation

The `gateway_simulator` generates deterministic test outcomes for simulated
payments. After a CI test run:
1. The outbox contains `payment.succeeded` and `payment.failed` events.
2. The Bronze ETL writes them to Floci.
3. The Silver ETL processes them.
4. DuckDB queries against Floci return realistic (if synthetic) results.

This allows ML training pipeline integration tests to run in CI without real
payment data. The synthetic data volume is small (hundreds of events per CI
run) but structurally correct.

---

## 16. Data Governance and Access Control

### Who can access what

| Layer | Access | Who |
|---|---|---|
| Bronze (raw) | Read-only | Data engineers, compliance (on request) |
| Silver (validated) | Read-only | Data scientists, analysts |
| Gold (business-ready) | Read | All analytics consumers |
| ML training datasets | Read | ML engineers only |
| Reports (regulatory) | Read + submit | Compliance team |

The operational databases (`core_db`, `portal_db`) are accessible only to the
application and the ops team for incident investigation. Data scientists and
analysts never have credentials to the operational databases.

### PII handling

| Data | Bronze treatment | Silver treatment | Gold treatment |
|---|---|---|---|
| Customer MSISDN | Full (in envelope JSON) | SHA-256 hash | Hash only |
| Customer name | Full (in envelope JSON) | Removed | Removed |
| Merchant name | Full (in envelope JSON) | Kept (business data) | Kept |
| API key prefix | Full (in envelope JSON) | Removed | Removed |
| Amount | Full (minor units integer) | Kept | Kept |

Bronze preserves the full event payload as emitted from Core. This is necessary
for replay and investigation. Access to Bronze is restricted to data engineers
and requires a separate approval process for analysts.

Silver and Gold remove or hash PII so that the analytics and ML layers operate
without access to personally identifiable information. This is a requirement
under Ghana's Data Protection Act (DPA) and Yagye's data processing policy.

---

## 17. Lambda Architecture — What We Are

Yagye's data platform is a **Lambda architecture**: a well-understood pattern
that combines a batch layer for correctness and historical reprocessing with a
streaming layer for low-latency ingestion.

```
┌───────────────────────────────────────────────────────────────────────────┐
│  LAMBDA ARCHITECTURE                                                       │
│                                                                           │
│  Operational DB (core_db)                                                 │
│      │                                                                    │
│      ├── STREAMING LAYER ──────────────────────────────────────────────►  │
│      │   Redpanda Connect → Bronze Parquet (< 30s lag)                    │
│      │                                                                    │
│      └── BATCH LAYER ────────────────────────────────────────────────►    │
│          DuckDB ETL jobs: Bronze → Silver → Gold                          │
│          Runs hourly (Silver) and nightly (Gold)                          │
│                                                                           │
│                        SERVING LAYER                                      │
│          DuckDB reads from Gold Parquet → ML scoring, BI, reports         │
└───────────────────────────────────────────────────────────────────────────┘
```

### Why not pure Kappa (stream-only)?

Kappa architecture is Lambda without the batch layer — all processing is done
in a single streaming pipeline. This sounds simpler: one code path, one
processing model. But Kappa has a critical weakness: **reprocessing**.

When a Silver ETL bug is discovered (e.g. a fee calculation was wrong for 3
months), reprocessing requires replaying 3 months of Kafka events through the
corrected pipeline. This requires:
- Kafka to have retained 3 months of events (expensive; most deployments retain
  7 days)
- The streaming pipeline to handle 3 months of events at catch-up speed without
  impacting real-time processing
- The stateful operators (joins, aggregations) to correctly handle out-of-order
  replay

Yagye's Bronze layer is the immutable event log. The DuckDB ETL can re-run
against Bronze at any time — it is not limited by a Kafka retention window.
Reprocessing 3 months of data with a corrected DuckDB SQL query is a
30-minute job, not a 3-day re-architecture. This reprocessing capability is
essential for a regulated financial system where historical data correctness
is non-negotiable.

### The trade-off

Lambda's cost is two code paths for similar logic:
- The Redpanda Connect pipeline handles raw event ingestion (streaming path).
- The DuckDB ETL handles transformation and enrichment (batch path).

Some logic — like PII hashing or timestamp normalisation — must be implemented
in both. At Yagye's scale, this duplication is acceptable: the batch logic is
simple SQL, not a stateful streaming topology. The correctability of batch
reprocessing is worth the duplication cost.

### When to migrate toward Kappa

If Yagye's data team grows to manage 50+ pipelines and the two-path duplication
becomes a significant maintenance burden, the migration path is to replace
DuckDB batch ETL with a stateful streaming processor (Apache Flink) and rely
on Redpanda's long retention for reprocessing. This is a 12–18-month project
at that scale, not a day-one decision.

---

## 18. Kimball Data Modeling — Fact and Dimension Tables

The Gold layer follows **Kimball dimensional modeling** (also called the star
schema): a design methodology for analytical databases that separates business
events (facts) from entity attributes (dimensions).

```
┌────────────────────────────────────────────────────────────────────────┐
│  STAR SCHEMA (Kimball)                                                 │
│                                                                        │
│  dim_merchants ──────┐                                                 │
│                      │                                                 │
│  dim_providers ──────┼──► fact_payments ◄── dim_pricing_rules         │
│                      │    (one row per                                 │
│  dim_time ───────────┘     payment event)                              │
│                                                                        │
│  fact tables: wide, append-only, high cardinality                      │
│  dim tables:  narrow, slowly changing, low-to-medium cardinality       │
└────────────────────────────────────────────────────────────────────────┘
```

### Fact tables

Fact tables capture business events. They are **append-only** (new events are
inserted; old rows are never updated) and contain foreign keys to dimension
tables plus numeric measures.

**`fact_payments`** — one row per payment lifecycle event

```
Columns:
  payment_id       text        -- Core public ID (pay_018e…)
  event_type       text        -- 'created' | 'dispatched' | 'succeeded' | 'failed'
  merchant_id      text        -- FK → dim_merchants.merchant_id
  provider_code    text        -- FK → dim_providers.provider_code
  customer_hash    text        -- SHA-256(msisdn)
  amount_minor     bigint      -- payment amount in pesewas
  fee_minor        bigint      -- platform fee in pesewas (0 until succeeded)
  mode             text        -- 'live' only in Gold
  network          text        -- 'mtn_gh' | 'voda_gh' | 'airtel_gh'
  currency         char(3)     -- 'GHS'
  event_at         timestamptz -- when this event occurred
  effective_date   date        -- partition key (for pruning)
  aggregate_version int        -- for ordering events on the same payment_id
```

**`fact_settlement_items`** — one row per settlement line item

```
Columns:
  settlement_id    text
  batch_id         text
  merchant_id      text        -- FK → dim_merchants
  provider_code    text        -- FK → dim_providers
  payment_count    int
  gross_amount     bigint
  fee_amount       bigint
  net_amount       bigint
  settled_at       timestamptz
  effective_date   date
```

**`fact_webhook_deliveries`** — one row per delivery attempt

```
Columns:
  delivery_id      text
  endpoint_id      text
  merchant_id      text        -- FK → dim_merchants
  event_type       text
  attempt_number   int
  http_status      int
  latency_ms       int
  succeeded        boolean
  attempted_at     timestamptz
  effective_date   date
```

### Dimension tables

Dimension tables capture entity attributes. They use SCD Type 2 (see §19) for
attributes that change over time.

**`dim_merchants`**

```
Columns:
  merchant_id      text
  business_name    text
  sector           text        -- 'retail' | 'fintech' | 'logistics' | ...
  country          char(2)     -- 'GH'
  kyb_tier         text        -- 'tier_1' | 'tier_2' | 'tier_3'
  status           text        -- 'active' | 'suspended' | 'terminated'
  valid_from       timestamptz -- SCD Type 2 effective start
  valid_to         timestamptz -- SCD Type 2 effective end (9999-12-31 = current)
```

**`dim_providers`**

```
Columns:
  provider_code    text        -- 'mtn_momo_gh'
  display_name     text        -- 'MTN MoMo Ghana'
  network          text        -- 'mtn_gh'
  country          char(2)     -- 'GH'
  kind             text        -- 'mobile_money' | 'card' | 'bank'
  valid_from       timestamptz
  valid_to         timestamptz
```

**`dim_pricing_rules`**

```
Columns:
  merchant_id      text
  provider_code    text
  fee_type         text        -- 'percentage' | 'fixed' | 'blended'
  fee_pct          numeric     -- e.g. 0.028 = 2.8%
  fee_fixed_minor  bigint      -- e.g. 50 = GHS 0.50 fixed component
  valid_from       timestamptz
  valid_to         timestamptz
```

### DuckDB handles star schema efficiently

DuckDB's query optimiser handles star schema joins natively. A query joining
`fact_payments` (10M rows) to `dim_merchants` (1,000 rows) uses a broadcast
hash join — the small dimension is loaded into memory and each fact row is
joined in a single pass. This is the core performance advantage of dimensional
modeling with a columnar engine.

---

## 19. Slowly Changing Dimensions (SCD) — A Critical Correctness Concern

**Slowly Changing Dimensions (SCDs)** are dimension attributes that change over
time. For a PSP, this is not an edge case — it is routine. Merchant fee tiers
change when pricing plans are updated. Provider health states change hourly.

If dimensions are stored as a single current-state row (SCD Type 1), historical
queries produce incorrect results. A Gold query for "what fees did we earn in
July?" using the **current** fee tier for merchants who changed plans in August
would overstate or understate revenue. This is not a display bug — it is a
financial reporting error.

### The three SCD types

**SCD Type 1 — Overwrite (wrong for Yagye)**

```
dim_merchants: merchant_id | status
Update: change status 'active' → 'suspended' overwrites the row.
```

Result: no history. All historical queries use the current status. A query for
"how many active merchants in Q1?" would exclude merchants who were active in Q1
but are now suspended. **Used for truly non-historical attributes only** (e.g.
display name corrections).

**SCD Type 2 — Effective-dated rows (Yagye's primary strategy)**

```
dim_merchants: merchant_id | status | valid_from       | valid_to
               mch_abc      active    2026-01-01 00:00   2026-09-15 14:23
               mch_abc      suspended 2026-09-15 14:23   9999-12-31 00:00  ← current
```

Historical queries join on `event_at BETWEEN valid_from AND valid_to`. A query
for Q1 merchant status correctly finds `active` (the row whose range covers Q1).

**SCD Type 3 — "Previous value" column (wrong for Yagye)**

```
dim_merchants: merchant_id | status    | previous_status
               mch_abc      suspended   active
```

Only one history level. A merchant who went `active → trial → suspended` loses
the intermediate state. Too inflexible for a PSP with multiple status transitions
per year.

### Which dimensions use SCD Type 2

| Dimension | Why it changes | What changes |
|---|---|---|
| `dim_pricing_rules` | Ops activates new pricing plan | `fee_pct`, `fee_fixed_minor` |
| `dim_merchants` | KYB tier upgrade, suspension | `status`, `kyb_tier` |
| `dim_providers` | Network changes, deprecation | `status`, `enabled_methods` |

### SCD Type 2 in practice: joining facts to dimensions

```sql
-- Correct: what fee rate applied to each payment at the time it occurred?
SELECT
  f.payment_id,
  f.amount_minor,
  f.event_at,
  d.fee_pct,
  ROUND(f.amount_minor * d.fee_pct)  AS computed_fee_minor
FROM gold.fact_payments f
JOIN gold.dim_pricing_rules d
  ON  d.merchant_id   = f.merchant_id
  AND d.provider_code = f.provider_code
  AND f.event_at BETWEEN d.valid_from AND d.valid_to
WHERE f.event_type = 'succeeded'
  AND f.effective_date BETWEEN '2026-07-01' AND '2026-07-31';
```

Without the `BETWEEN valid_from AND valid_to` predicate, a merchant whose fee
changed from 2.5% to 2.8% in August would have all July payments attributed at
2.8%. The query would overstate July revenue by 0.3% of gross volume — a real
discrepancy that would show up in reconciliation against the ledger.

### How the ETL maintains SCD Type 2

When a `pricing_plan.activated` event arrives in Bronze:

```python
# DuckDB ETL: update dim_pricing_rules on plan activation
con.execute("""
  -- Close the current row
  UPDATE gold.dim_pricing_rules
  SET valid_to = $event_at
  WHERE merchant_id = $merchant_id
    AND provider_code = $provider_code
    AND valid_to = '9999-12-31 00:00:00+00';

  -- Open a new row
  INSERT INTO gold.dim_pricing_rules
    (merchant_id, provider_code, fee_type, fee_pct, fee_fixed_minor,
     valid_from, valid_to)
  VALUES
    ($merchant_id, $provider_code, $fee_type, $new_fee_pct, $new_fee_fixed,
     $event_at, '9999-12-31 00:00:00+00');
""")
```

The ETL reads `pricing_plan.activated` events from Bronze. This event type must
be included in the outbox relay's topic list — if it is missing, the dimension
table will not reflect plan changes and historical fee queries will be incorrect.

---

## 20. Data Marts

The Gold layer is partitioned into **domain-specific data marts**: separate S3
prefixes, each serving one business domain with its own fact and dimension tables.

```
s3://yagye-lake-gold/
  payments-mart/           ← Payments Mart
    fact_payments/
    dim_merchants/
    dim_providers/
    dim_pricing_rules/
    payments_daily/        ← pre-aggregated for dashboards
  risk-mart/               ← Risk Mart
    risk_features_hourly/
    merchant_velocity_daily/
    chargeback_history/
  ops-mart/                ← Ops Mart
    fact_settlement_items/
    reconciliation_breaks/
    fact_webhook_deliveries/
```

### Payments Mart

**Owner:** Finance and Analytics teams  
**Primary consumers:** Revenue dashboards (Grafana/ECharts in portal), BoG regulatory reports, executive P&L  
**Key tables:** `fact_payments`, `dim_merchants`, `dim_providers`, `dim_pricing_rules`, `payments_daily`

The Payments Mart answers: "How much money moved, where did it go, and what did we earn?"

### Risk Mart

**Owner:** ML and Risk teams  
**Primary consumers:** Risk scorer training pipeline, reserve recommender, fraud analyst investigations  
**Key tables:** `risk_features_hourly`, `merchant_velocity_daily`, `chargeback_history`

The Risk Mart answers: "Which customers and merchants are exhibiting risk signals?" It feeds the ML training pipeline directly — the risk scorer is trained on Risk Mart features.

### Ops Mart

**Owner:** Operations team  
**Primary consumers:** Settlement reconciliation reports, webhook health dashboard, provider performance monitoring  
**Key tables:** `fact_settlement_items`, `reconciliation_breaks`, `fact_webhook_deliveries`, `provider_health_hourly`

The Ops Mart answers: "Is everything working? Where are the breaks?"

### Mart boundaries and cross-mart joins

Each mart owns its fact and dimension tables. Cross-mart joins are allowed but
should be exceptional. If the same dimension table (e.g. `dim_merchants`) is
needed by multiple marts, it is referenced from the Payments Mart as the
canonical source — other marts read from it via S3 path reference, not a copy.

This mart boundary is the foundation for a future **Data Mesh** pattern if
Yagye grows to the scale where separate engineering teams own each domain
independently. For now, all three marts are operated by one data engineering
function.

---

## 21. Data Mesh vs Centralized Architecture

Yagye chose a **centralized data platform** over a Data Mesh, and this was a
deliberate decision, not an oversight.

### What Data Mesh is

Data Mesh is a decentralized approach where each product domain owns its own
data pipelines, data contracts, and data quality guarantees. The analytics
platform is replaced by a federation of domain-owned data products. A central
platform team provides infrastructure primitives (object storage, a query bus)
but not the pipelines.

Data Mesh is appropriate when:
- Multiple autonomous product teams each generate and consume large data volumes
- Each team needs independent data SLAs (the payments team cannot wait for the
  risk team to fix a broken pipeline)
- Governance must be federated (central governance becomes a bottleneck at scale)
- Each domain team has dedicated data engineering resources

### Why centralized is correct for Yagye now

Yagye currently has:
- **One engineering team** responsible for all platform domains
- **One data engineering function** (not per-domain)
- **Three data consumers**: analytics, ops, ML — all internal to Yagye
- **One regulatory regime**: BoG reporting is cross-domain by definition

A Data Mesh at this scale would mean:
- Three separate pipeline codebases to maintain instead of one
- Three separate infrastructure deployments (three sets of S3 buckets, three
  Redpanda Connect instances, three ETL schedulers)
- Three sets of data quality monitoring
- Cross-mart joins (which are routine in Yagye's reporting) require cross-domain
  contracts and coordination

The mart-based partition within the centralized platform gives domain clarity
(each mart has a clear owner and consumers) without the federation overhead.

### When to reconsider

Revisit this decision when:
- More than 3 engineering teams own independent data domains with independent
  release cycles
- Cross-team coordination on data pipeline changes becomes a regular bottleneck
- Each domain team has a dedicated data engineer

At that point, the mart boundaries already established map cleanly to Data Mesh
domains. The migration is organisational (team ownership model) more than
technical — the S3 prefixes, schemas, and ETL scripts remain largely unchanged.

---

## 22. Orchestration — Oban Instead of Airflow/Dagster

Yagye's ETL pipeline is orchestrated by **Oban**, not Airflow, Dagster, or
Prefect. This is an intentional choice that trades ecosystem tooling for
operational simplicity.

### Why not Airflow?

Apache Airflow is the dominant open-source orchestration tool for data pipelines.
It provides: a directed acyclic graph (DAG) model for expressing dependencies,
a web UI for monitoring pipeline runs, retry and alerting infrastructure, a
large plugin ecosystem, and templated SQL operators.

Adding Airflow to Yagye's stack means:
- **A new service to operate:** Airflow requires a scheduler process, a web
  server, a Celery or Kubernetes executor, and its own PostgreSQL metadata
  database. That is four new processes and one new database.
- **A new language boundary:** DAGs are Python. Yagye's application code is
  Elixir. Cross-language debugging of a failed ETL job that originated in an
  Elixir outbox event requires context-switching across two languages and two
  observability systems.
- **A separate monitoring UI:** Airflow's web UI is separate from Grafana.
  Yagye's ops team would need to monitor two dashboards for pipeline health.

### How Oban replaces Airflow

ETL jobs are Python scripts executed via a thin `PythonWorker` Oban job:

```elixir
defmodule YagyeCore.Workers.SilverPaymentsETLWorker do
  use Oban.Worker, queue: :data_engineering, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    System.cmd("python3", [
      "scripts/etl/silver_payments.py",
      "--env=#{Application.get_env(:yagye_core, :env)}",
      "--watermark=auto"
    ])
    |> case do
      {_output, 0} -> :ok
      {output, code} -> {:error, "ETL exit #{code}: #{output}"}
    end
  end
end
```

This means ETL jobs:
- Share Oban's retry and alerting infrastructure (no new tooling)
- Appear in the same Grafana dashboard as payment and projection workers
- Use the same structured log format (Python scripts emit JSON to stdout)
- Are scheduled via Oban's cron plugin (same mechanism as `OutboxRelayWorker`)

Dependency between ETL steps (Bronze → Silver → Gold) is expressed as Oban job
chaining: the Silver ETL job inserts a Gold ETL job into the queue on success.

### Migration path

If ETL pipelines grow beyond ~20 steps with complex fan-out, conditional
branching, and SLA-based alerting requirements, **Dagster** is the preferred
migration target over Airflow:

- Dagster's asset-based model (each table is an asset with dependencies) maps
  more naturally to Yagye's medallion layers than Airflow's operator DAG model
- Dagster has better Python integration and type safety
- Dagster's UI is more approachable than Airflow's for engineers who are not
  data platform specialists
- The Python ETL scripts are unchanged — only the scheduling wrapper changes

---

## 23. DBT vs Raw DuckDB SQL

Yagye's ETL scripts use raw DuckDB SQL, not **dbt** (data build tool). This
is a considered choice with a clear migration path.

### What dbt provides

dbt is a transformation framework for data pipelines. It provides:
- **SQL templating** via Jinja: `{{ ref('silver_payments') }}` generates the
  correct S3 path for the upstream model
- **Dependency graph**: dbt infers which models depend on which and runs them
  in the correct order, with parallelism
- **Incremental models**: `{{ is_incremental() }}` logic for watermark-based
  processing
- **Tests**: schema tests (`not_null`, `unique`) and custom SQL tests run after
  each model materialisation
- **Documentation**: auto-generates a web UI showing model lineage and column
  descriptions

### Why Yagye uses raw SQL instead

**The ETL is a small number of Python scripts.** At current scope — four Silver
jobs and four Gold jobs — dbt's abstraction layer adds more complexity than it
removes.

Concretely:
- `dbt-duckdb` is a third-party adapter (not maintained by dbt Core). The
  DuckDB `httpfs` S3 extension requires specific initialisation that the adapter
  may not handle transparently.
- dbt requires `profiles.yml`, `dbt_project.yml`, and a specific project
  directory structure. That is boilerplate for eight scripts.
- The dependency between ETL steps (Bronze → Silver → Gold) is already expressed
  in Oban's job queue. Adding dbt's dependency graph would duplicate this
  dependency in a second system.
- Jinja templating inside SQL strings inside Python is three layers of
  indirection. Plain Python f-strings for parameterised queries are simpler
  and more readable.

### The migration trigger

Adopt `dbt-duckdb` when:
- The number of Gold models exceeds ~20 (the dependency graph becomes hard to
  manage with Oban chaining alone)
- Test coverage of Silver and Gold tables is difficult to maintain with custom
  Python assertions
- A new data engineer joins and needs to navigate the pipeline — dbt's
  documentation UI would significantly improve onboarding

When that migration happens, the SQL models are already written. Moving them
into dbt model files (`.sql`) with a `{{ ref() }}` header is a mechanical
translation, not a rewrite. The DuckDB ETL scripts become dbt models; the
Python wrappers become dbt hooks or are removed.

```sql
-- Current: Python f-string
query = f"""
  SELECT * FROM read_parquet('{silver_path}/payments/**/*.parquet')
  WHERE effective_date >= '{watermark}'
"""

-- Future dbt model: models/gold/fact_payments.sql
SELECT * FROM {{ ref('silver_payments') }}
WHERE effective_date >= '{{ var("watermark") }}'
```

The substance is identical. dbt adds discoverability and test infrastructure
at the cost of a new toolchain dependency.

---

## 24. Data Lineage

**Data lineage** is the ability to answer: "Where did this number come from?"
For a Gold metric like "MTN MoMo success rate for July 2026", lineage means
being able to trace the answer back through:

```
Gold: provider_health_hourly (aggregated)
  ← Silver: silver_payment_events (validated, enriched)
    ← Bronze: yagye.payments.events (raw Parquet, immutable)
      ← Core DB: payment_attempts table (OLTP row)
        ← Outbox: outbox_events table (event_id = ulid_xyz)
          ← Application: PaymentAttemptWorker dispatched at 14:32:07
```

Without lineage, regulators can ask "prove your July MoMo figure is correct"
and Yagye cannot answer definitively — it can only assert that the query is
correct. With lineage, Yagye can trace every Gold row back to the raw Bronze
event that produced it, and from there to the original database transaction.

### Why lineage matters in a PSP

Ghana's Data Protection Act and the Bank of Ghana's Electronic Money Issuer
guidelines require that reported figures can be audited to source. If a BoG
examiner challenges a reported settlement volume, Yagye must produce the
source records. Lineage is the audit trail.

Beyond compliance: when a data bug is found in Gold, lineage tells the team
exactly which Bronze events were affected, what the correct values should be,
and which Gold tables need recomputation. Without lineage, the scope of a bug
is unknown — the team must re-run everything to be safe.

### How Yagye implements lineage

Lineage is maintained at three levels:

**1. Event-level: outbox event_id on every Bronze record**

Every Bronze Parquet row carries `event_id` (the ULID from the outbox table).
This is the root anchor. Any Gold row can be traced to a set of Bronze event
IDs, which can be cross-referenced against Core's outbox table.

```
gold.fact_payments.payment_id = 'pay_018e...'
  → silver.silver_payment_events WHERE payment_id = 'pay_018e...'
    → bronze.payments_events WHERE payment_id = 'pay_018e...'
      → event_id = '01J5QKRB5G000000000000000A'
        → SELECT * FROM core_db.outbox_events WHERE event_id = '...'
```

**2. ETL-level: job metadata on every ETL run**

Each DuckDB ETL script writes a `_etl_meta.json` file alongside the Parquet
output it produces:

```json
{
  "job": "silver_payments_etl",
  "run_id": "run_20261018_143200",
  "watermark_from": "2026-10-17T14:00:00Z",
  "watermark_to":   "2026-10-18T14:00:00Z",
  "input_files": [
    "s3://yagye-lake-bronze/payments-events/2026/10/17/...",
    "s3://yagye-lake-bronze/payments-events/2026/10/18/..."
  ],
  "output_files": [
    "s3://yagye-lake-silver/payments/2026/10/18/part-00001.parquet"
  ],
  "rows_read": 142800,
  "rows_written": 142791,
  "rows_rejected": 9,
  "script_git_sha": "a3f8b12"
}
```

`script_git_sha` records which version of the ETL script produced this output.
If a bug is found in commit `a3f8b12`, the team can query `_etl_meta.json`
files to find every Parquet file produced by that script version and recompute
only those files.

**3. Schema-level: column provenance in Gold table comments**

Each Gold table's schema file includes column-level provenance notes:

```sql
-- gold.fact_payments
-- payment_id:    Source: silver.silver_payment_events.payment_id
-- fee_minor:     Source: silver.fee_records.fee_minor (joined on payment_id + event_type='succeeded')
-- event_at:      Source: bronze.payments_events.occurred_at (no transformation)
-- effective_date: Derived: DATE_TRUNC('day', event_at AT TIME ZONE 'Africa/Accra')
```

This is lightweight documentation, not a formal lineage graph. If the data
platform grows to 30+ Gold models, the migration path is to adopt a lineage
tool (Apache Atlas, OpenLineage, or Marquez) that captures lineage from ETL
job runs automatically. At the current scale of 8 models, inline documentation
is sufficient.

### The reprocessing-lineage relationship

Lineage and reprocessing are inseparable. When a Silver ETL bug is discovered:

```
1. Identify affected run_ids from _etl_meta.json (which runs used the buggy script)
2. Identify affected output files (which Silver Parquet partitions to invalidate)
3. Re-run Silver ETL for those date partitions (DuckDB reads from immutable Bronze)
4. Re-run Gold ETL for the downstream partitions
5. Verify: re-run the original query; compare to the previously reported figure
6. If a report was already filed with BoG, submit a corrected report with diff
```

This workflow is only possible because Bronze is immutable (S3 Object Lock)
and every ETL run records its input files. If Bronze were mutable, step 3
would not be reliable — the "source of truth" could itself have been altered.

---

## 25. Pipeline Testing and Data Quality

A data pipeline without tests is a pipeline that silently produces wrong
numbers. In a PSP, wrong numbers mean wrong regulatory reports, wrong merchant
settlements, and wrong risk scores. Testing the pipeline is not optional.

### Three layers of testing

**Layer 1: Schema tests (structural correctness)**

Run immediately after each ETL job materialises a new Parquet partition.
These are fast checks that catch broken pipelines early.

```python
def assert_schema(df: pd.DataFrame, table: str):
    """Assert column presence and nullability contracts."""
    required_non_null = {
        "silver_payment_events": [
            "payment_id", "merchant_id", "event_type",
            "amount_minor", "event_at", "effective_date"
        ],
        "fact_payments": [
            "payment_id", "merchant_id", "provider_code",
            "amount_minor", "event_at", "effective_date"
        ],
    }

    for col in required_non_null.get(table, []):
        null_count = df[col].isna().sum()
        assert null_count == 0, (
            f"[{table}] Column '{col}' has {null_count} null rows — "
            f"violates not-null contract"
        )
```

**Layer 2: Business rule tests (semantic correctness)**

Run after Silver ETL. These catch bugs in transformation logic that schema
tests cannot catch — data that is structurally valid but semantically wrong.

```python
def assert_silver_business_rules(con: duckdb.DuckDBPyConnection):
    # Amounts must be positive integers
    con.execute("""
        SELECT COUNT(*) FROM silver_payment_events
        WHERE amount_minor <= 0
    """).fetchone()[0] == 0 or raise AssertionError("Negative amounts in silver")

    # Every succeeded event must have a fee record
    broken = con.execute("""
        SELECT COUNT(*) FROM silver_payment_events e
        LEFT JOIN silver_fee_records f ON f.payment_id = e.payment_id
        WHERE e.event_type = 'succeeded' AND f.payment_id IS NULL
    """).fetchone()[0]
    assert broken == 0, f"{broken} succeeded payments have no fee record"

    # Mode must be live only in Gold (Silver still carries all modes)
    # No assertion here — assertion lives in Gold tests

    # event_at must be within the declared watermark range
    out_of_window = con.execute("""
        SELECT COUNT(*) FROM silver_payment_events
        WHERE event_at < $watermark_from OR event_at > $watermark_to
    """, {"watermark_from": wm_from, "watermark_to": wm_to}).fetchone()[0]
    assert out_of_window == 0, f"{out_of_window} rows outside watermark window"
```

**Layer 3: Cross-layer consistency tests (financial correctness)**

Run nightly after Gold ETL completes. These are the most important tests
because they catch bugs that produce wrong financial figures.

```python
def assert_gold_consistency(con: duckdb.DuckDBPyConnection):
    # 1. Sum of Gold fact_payments amounts must equal sum of Silver amounts
    #    for the same date range (no rows lost or duplicated in Gold ETL)
    silver_sum = con.execute("""
        SELECT SUM(amount_minor) FROM silver_payment_events
        WHERE event_type = 'succeeded' AND mode = 'live'
          AND effective_date BETWEEN $from AND $to
    """).fetchone()[0]

    gold_sum = con.execute("""
        SELECT SUM(amount_minor) FROM gold.fact_payments
        WHERE event_type = 'succeeded'
          AND effective_date BETWEEN $from AND $to
    """).fetchone()[0]

    assert silver_sum == gold_sum, (
        f"Gold/Silver sum mismatch: silver={silver_sum} gold={gold_sum} "
        f"diff={gold_sum - silver_sum}"
    )

    # 2. Every Gold payment_id must exist in Core via the Silver anchor
    orphans = con.execute("""
        SELECT COUNT(*) FROM gold.fact_payments g
        LEFT JOIN silver_payment_events s ON s.payment_id = g.payment_id
        WHERE s.payment_id IS NULL
    """).fetchone()[0]
    assert orphans == 0, f"{orphans} Gold rows have no Silver source"

    # 3. Settlement amounts must reconcile against ledger postings
    # (run monthly for regulatory report sign-off)
    settlement_gold = con.execute("""
        SELECT SUM(net_amount) FROM gold.fact_settlement_items
        WHERE settled_at::date BETWEEN $from AND $to
    """).fetchone()[0]

    ledger_credits = con.execute("""
        SELECT SUM(amount) FROM silver_ledger_postings
        WHERE account_type = 'merchant_payable'
          AND direction = 'credit'
          AND posted_at::date BETWEEN $from AND $to
    """).fetchone()[0]

    assert abs(settlement_gold - ledger_credits) < 1, (
        f"Settlement/ledger mismatch: gold={settlement_gold} "
        f"ledger={ledger_credits}"
    )
```

### Why the sum-zero test matters

The Gold-to-Silver sum reconciliation (test 1 above) is the data equivalent
of the double-entry sum-zero check in the ledger. If Gold volume differs from
Silver volume for the same date range, one of three things happened:

- Rows were dropped by the Gold ETL filter (e.g. `mode = 'live'` excluded
  rows it should not have)
- Rows were duplicated by a watermark boundary overlap
- An amount field was transformed incorrectly (e.g. currency conversion applied
  twice)

Running this test nightly means the window between a bug introduction and its
detection is at most 24 hours, not "whenever someone notices the dashboard is
wrong."

### Failure handling

Failed tests emit a structured Loki log entry and create an Oban job that
alerts the data engineering on-call channel. Importantly, the failed partition
is **not promoted to Gold** — it stays in Silver staging until the test passes.
This prevents a broken ETL run from silently overwriting a good Gold partition.

---

## 26. AI Layer 1 — LLM Enrichment

LLM enrichment is the first AI layer on top of the medallion pipeline. It uses
a language model to extract structured information from unstructured text fields
that exist in the operational data — information that cannot be derived by SQL
alone.

### What problems LLM enrichment solves

Yagye's operational data contains several free-text fields:

| Field | Source | Problem |
|---|---|---|
| `merchant.business_description` | KYB onboarding form | Merchants self-describe. "We sell phones" and "Mobile device retail" are the same sector but different strings. |
| `payment_attempt.failure_reason` | Provider API response | MTN returns "INSUFFICIENT_FUNDS"; Vodafone returns "ERR_BALANCE_LOW". Same failure, different strings. |
| `screening_hit.hit_details` | AML/sanctions check | JSON blob with free-text name matches, varying structure per screening provider. |
| `chargeback.dispute_reason` | Scheme dispute codes | Codes plus free-text merchant responses of varying quality. |

Without enrichment, grouping "all payments that failed due to insufficient
funds" requires maintaining a manual mapping of every provider's failure codes.
This mapping breaks every time a provider changes their error strings.

### What enrichment produces

The enrichment pipeline runs as a weekly Gold-layer job. It reads Silver fields,
calls a Claude API endpoint, and writes structured tags back to a Gold enrichment
table:

```
silver_payment_events.failure_reason = "ERR_BALANCE_LOW"
                                     ↓  LLM enrichment
gold_enriched_failures.failure_category = "insufficient_funds"
gold_enriched_failures.is_customer_fault = true
gold_enriched_failures.retry_likely_to_succeed = false
```

```
silver_merchants.business_description = "We supply building materials to contractors"
                                      ↓  LLM enrichment
gold_enriched_merchants.sector_code = "construction_materials"
gold_enriched_merchants.sector_confidence = 0.94
gold_enriched_merchants.is_b2b = true
```

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  LLM ENRICHMENT PIPELINE                                                 │
│                                                                         │
│  Silver Parquet ──► Enrichment ETL (Python) ──► Claude API              │
│                          │                        (batch, async)        │
│                          │                            │                 │
│                          ▼                            ▼                 │
│                    Rate limiter              Structured JSON response   │
│                    (1000 rows/min)                     │                │
│                                                        ▼                │
│                                             gold_enriched_* tables      │
│                                             (Parquet, weekly refresh)   │
└─────────────────────────────────────────────────────────────────────────┘
```

```python
import anthropic
import json

client = anthropic.Anthropic()

def enrich_failure_reason(raw_reason: str) -> dict:
    """Map a raw provider failure string to a structured category."""
    response = client.messages.create(
        model="claude-haiku-5-5",   # Fast, cheap for classification tasks
        max_tokens=200,
        messages=[{
            "role": "user",
            "content": f"""Classify this payment failure reason into a structured category.

Raw provider message: "{raw_reason}"

Return JSON with these fields:
- failure_category: one of [insufficient_funds, account_not_found, network_timeout,
  provider_error, limit_exceeded, invalid_credentials, user_cancelled, unknown]
- is_customer_fault: boolean (true = customer action required; false = provider/system issue)
- retry_likely_to_succeed: boolean

Return only the JSON object, no other text."""
        }]
    )
    return json.loads(response.content[0].text)
```

**Why `claude-haiku-5-5`:** Classification tasks like this are pattern-matching,
not reasoning. Haiku is 5–10x cheaper than Sonnet for comparable accuracy on
structured extraction tasks with a clear schema. The savings matter when running
this against millions of historical failure records.

### Advantages of LLM enrichment

- **Eliminates manual mapping maintenance.** No more updating a 200-row CSV
  every time MTN changes an error code.
- **Cross-provider normalisation.** A single `failure_category = 'insufficient_funds'`
  tag covers all provider-specific strings — making cross-provider dashboards
  accurate.
- **Enables better ML features.** The risk scorer can use `failure_category`
  as a feature — "this customer has had 5 'insufficient_funds' failures in 24h"
  is a better feature than a raw string matching heuristic.
- **Merchant sector accuracy.** Self-reported sectors are noisy; LLM-enriched
  sectors are more consistent, improving the accuracy of sector-based analytics
  and reserve recommendations.

### Quality control

Enrichment output is not trusted blindly. The pipeline:

1. Samples 2% of outputs and writes them to a human-review queue (Postgres
   table visible to the data team in the portal)
2. Computes inter-rater agreement: for categories where the previous week's
   outputs are re-run, agreement must be ≥ 95%
3. Keeps the raw source field alongside the enriched field — enrichment is
   additive, not destructive

---

## 27. AI Layer 2 — RAG Chatbot on Analytics Data

A **RAG (Retrieval-Augmented Generation) chatbot** allows Yagye's ops and
finance teams to ask natural language questions about the analytics data and
receive accurate, sourced answers — without writing SQL.

### The problem it solves

The ops team wants to know: "Which merchants had the highest decline rates last
week and what were the primary failure reasons?" Without a chatbot, this
requires:
- A data analyst to write a query
- The analyst to know which Gold tables to use
- A 30-minute turnaround if the analyst is busy

With a RAG chatbot, an ops manager types the question and gets an answer in
seconds — with the source query shown so they can verify it.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  RAG CHATBOT ARCHITECTURE                                                │
│                                                                         │
│  User question (natural language)                                       │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────┐     ┌─────────────────────────────────────────┐   │
│  │  Vector Search  │     │  Gold Table Metadata (schema + samples)  │   │
│  │  (embeddings of │────►│  "fact_payments has columns: payment_id, │   │
│  │  Gold schemas   │     │   amount_minor, event_at, provider_code" │   │
│  │  + past queries)│     └─────────────────────────────────────────┘   │
│  └─────────────────┘                    │                               │
│                                         ▼                               │
│                              ┌──────────────────┐                       │
│                              │  LLM (Sonnet 5.5) │                       │
│                              │  "Given these     │                       │
│                              │   schemas, answer │                       │
│                              │   the question"   │                       │
│                              └──────────────────┘                       │
│                                         │                               │
│                                         ▼                               │
│                              Structured answer +                        │
│                              cited DuckDB SQL query                     │
│                                         │                               │
│                                         ▼                               │
│                              DuckDB executes query on Gold Parquet       │
│                                         │                               │
│                                         ▼                               │
│                              Result table + answer displayed in portal  │
└─────────────────────────────────────────────────────────────────────────┘
```

### The RAG component

RAG (Retrieval-Augmented Generation) means the LLM does not answer from its
training knowledge alone — it is given relevant context retrieved from a
knowledge base before generating its answer.

For the analytics chatbot, the knowledge base contains:

1. **Gold table schemas** — column names, types, descriptions, sample values
2. **Past successful queries** — questions that were previously asked and the
   SQL that answered them correctly (stored in a `query_library` table)
3. **Business glossary** — domain-specific terms: "what is a settlement batch?",
   "what does kyb_tier mean?"

When the user asks a question, a vector similarity search finds the most
relevant schemas and past queries. These are injected into the LLM prompt as
context. The LLM then generates a SQL query grounded in the actual schema —
not hallucinated column names.

```python
def answer_analytics_question(question: str) -> dict:
    # 1. Retrieve relevant context
    relevant_schemas = vector_search(question, corpus="gold_schemas", top_k=3)
    relevant_queries = vector_search(question, corpus="query_library", top_k=5)

    # 2. Build grounded prompt
    context = format_context(relevant_schemas, relevant_queries)

    response = client.messages.create(
        model="claude-sonnet-5-5",  # Sonnet for multi-step reasoning on schema
        max_tokens=1000,
        system="""You are a data analyst assistant for Yagye, a payment service
provider in Ghana. You answer questions about payment analytics by writing
DuckDB SQL queries against the Gold layer tables.

Rules:
- Only reference tables and columns that exist in the provided schemas
- All monetary amounts are in minor units (pesewas). Convert to GHS in output.
- Gold tables only contain live mode data
- Always include a WHERE effective_date filter for time-bounded questions
- Return: {"sql": "...", "explanation": "..."}""",
        messages=[{
            "role": "user",
            "content": f"""Context (Gold table schemas and example queries):
{context}

Question: {question}"""
        }]
    )

    result = json.loads(response.content[0].text)

    # 3. Execute the generated SQL against Gold Parquet
    con = duckdb.connect()
    data = con.execute(result["sql"]).df()

    return {
        "answer": result["explanation"],
        "sql": result["sql"],
        "data": data.to_dict(orient="records")
    }
```

### Why RAG and not fine-tuning?

Fine-tuning a model on Yagye's SQL queries would produce a model that knows
the schema at training time. As the schema evolves (new Gold tables, renamed
columns), the fine-tuned model becomes stale — requiring a new fine-tuning run.

RAG is schema-agnostic: when a new Gold table is added, its schema is added
to the knowledge base. The next query that touches it will retrieve the updated
schema and the LLM will use it correctly. No retraining required.

### Access control

The RAG chatbot is an internal tool (Portal, ops-facing). It enforces the same
RBAC as the rest of the portal — users with `ops_analyst` role can query
payment and settlement data; `compliance_analyst` can additionally query risk
and screening data. The SQL generated by the LLM is parameterised with the
user's scope before execution:

```sql
-- Always injected: scope filter based on user's merchant scope
-- Ops users: no merchant filter (see all merchants)
-- Merchant users: WHERE merchant_id = $current_merchant_id
```

---

## 28. AI Layer 3 — Text-to-SQL for Merchants

Text-to-SQL gives individual merchants a self-service analytics interface:
they type a question about their own payment data in natural language and get
a table back — no SQL required, no analyst involvement.

### Why it is separate from the RAG chatbot (§27)

The RAG chatbot (§27) is for internal Yagye ops users. It has access to
cross-merchant data and complex Gold tables. A merchant should never see another
merchant's data.

Text-to-SQL for merchants is:
- **Scoped to that merchant's data only** — every generated query is
  automatically filtered by `merchant_id = $merchant_id`
- **Simpler schema** — merchants query a subset of Gold tables exposed via a
  merchant-facing view layer
- **Simpler questions** — "how much did I process last month?" not "compare
  MTN and Vodafone decline rates across all merchants in sector X"

### Merchant-facing view layer

Rather than exposing full Gold tables to the text-to-SQL system, a view layer
defines what merchants can see:

```sql
-- Merchant-scoped payment summary view
CREATE VIEW merchant_payments AS
SELECT
  payment_id,
  amount_minor / 100.0             AS amount_ghs,
  fee_minor / 100.0                AS fee_ghs,
  (amount_minor - fee_minor) / 100.0 AS net_ghs,
  network,
  event_type,
  event_at,
  effective_date
FROM gold.fact_payments
WHERE merchant_id = current_setting('app.merchant_id')
  AND mode = 'live';

-- Merchant-scoped settlement view
CREATE VIEW merchant_settlements AS
SELECT
  settlement_id,
  payment_count,
  gross_amount / 100.0  AS gross_ghs,
  fee_amount / 100.0    AS fee_ghs,
  net_amount / 100.0    AS net_ghs,
  settled_at
FROM gold.fact_settlement_items
WHERE merchant_id = current_setting('app.merchant_id');
```

The LLM is given only these view schemas — it cannot see or query full Gold
tables. Even if the LLM were to generate a query against `gold.fact_payments`
directly (which it should not, given only view schemas in context), the
query would be rejected by the execution layer.

### How it works

```python
def merchant_text_to_sql(question: str, merchant_id: str) -> dict:
    # Only merchant-scoped view schemas in context
    schema_context = load_merchant_view_schemas()

    response = client.messages.create(
        model="claude-haiku-5-5",   # Haiku sufficient for simpler merchant queries
        max_tokens=500,
        system=f"""You are a data assistant for a merchant using Yagye payment
processing. Answer questions about their payment data using SQL.

Available views (DO NOT reference any other tables):
{schema_context}

Rules:
- Only use the listed views, never underlying tables
- Amounts are already in GHS (no conversion needed)
- Return: {{"sql": "...", "explanation": "plain English explanation"}}
- If you cannot answer the question with these views, return:
  {{"sql": null, "explanation": "I cannot answer that question"}}""",
        messages=[{"role": "user", "content": question}]
    )

    result = json.loads(response.content[0].text)
    if result["sql"] is None:
        return {"answer": result["explanation"], "data": []}

    # Execute with merchant_id set as a session variable
    con = duckdb.connect()
    con.execute(f"SET app.merchant_id = '{merchant_id}'")
    data = con.execute(result["sql"]).df()

    return {
        "answer": result["explanation"],
        "sql": result["sql"],     # Shown to merchant for transparency
        "data": data.to_dict(orient="records")
    }
```

### Example interactions

```
Merchant: "How much did I process in September?"

Generated SQL:
  SELECT SUM(amount_ghs) AS total_ghs, COUNT(*) AS payment_count
  FROM merchant_payments
  WHERE event_type = 'succeeded'
    AND effective_date BETWEEN '2026-09-01' AND '2026-09-30'

Answer: "You processed GHS 48,320.50 across 1,204 successful payments in September."

---

Merchant: "Which days had the most failures last month?"

Generated SQL:
  SELECT effective_date, COUNT(*) AS failed_count
  FROM merchant_payments
  WHERE event_type = 'failed'
    AND effective_date >= date_trunc('month', current_date) - INTERVAL '1 month'
    AND effective_date <  date_trunc('month', current_date)
  GROUP BY effective_date
  ORDER BY failed_count DESC
  LIMIT 10

Answer: "September 15 had the most failures (23), followed by September 22 (18)."
```

### Safety guardrails

The text-to-SQL layer enforces three safety layers:

1. **Schema isolation** — the LLM only receives merchant-scoped view schemas
2. **Query validation** — the generated SQL is parsed before execution; any
   reference to a table not in the approved view list is rejected with an error
3. **Row limit** — all merchant text-to-SQL queries are capped at 10,000 rows;
   queries that would return more are rejected with "please narrow your date range"

### Advantages over pre-built dashboards

Pre-built dashboards answer the questions the product team anticipated.
Text-to-SQL answers questions the product team did not anticipate. A merchant
who wants "payments between GHS 100 and GHS 200 that failed on Fridays in Q3"
gets that answer immediately — no feature request, no analyst, no waiting.

This directly improves merchant retention: merchants who can self-serve their
analytics questions have less reason to switch to a competitor who offers more
reports.

---

## 29. Data Architecture Evolution and Where Yagye Sits

Understanding the industry's architectural evolution clarifies why Yagye made
the choices it did and what the next step looks like.

### Data Warehouse (1980s–2000s)

The first large-scale analytical architecture. A data warehouse (Teradata, Oracle,
later Redshift, Snowflake) is a structured, schema-on-write system:

- Data is transformed and loaded into a fixed schema before storage
- Queries are fast because the schema is optimised for analytics (columnar storage,
  pre-aggregated summaries)
- Rigid: schema changes require ETL pipeline changes and re-loading data
- Expensive: cloud data warehouses charge per query and per storage separately
- No support for unstructured data (images, JSON events, text)

**Why Yagye didn't choose a warehouse:**
At Yagye's current scale, a Snowflake warehouse is operationally expensive and
architecturally rigid. Bronze events are semi-structured JSON — they don't fit
naturally into a fixed schema. A warehouse would require a schema for every
possible event payload, maintained in sync with Core's event definitions.

### Data Lake (2010s)

The reaction to warehouse rigidity. A data lake (HDFS, then S3) stores raw data
in its native format — JSON, CSV, Parquet, images — at low cost. Schema is
determined at query time (schema-on-read).

- Cheap storage (S3 costs a fraction of a warehouse)
- Flexible: any data type can be stored
- Slow queries: no indexing, no pre-computation; reading 1TB of raw JSON for
  every query is slow
- "Data swamp" risk: without governance, a data lake becomes an unorganised
  collection of files that nobody trusts

**Why Yagye didn't stop at a data lake:**
Bronze is effectively a data lake. Raw, unprocessed, append-only, cheap. But
Bronze alone cannot serve analytics queries — it is too slow and too raw for
business users to query directly.

### Lakehouse (2020s — Yagye's choice)

The lakehouse combines the low-cost flexible storage of a data lake with the
query performance and structure of a data warehouse. Key innovations:

- **Parquet format** brings columnar storage and compression (warehouse-like
  performance) to S3 (lake-like costs)
- **DuckDB** provides an in-process SQL engine that reads Parquet from S3 with
  partition pruning — fast analytical queries without a warehouse service
- **Medallion architecture** provides the governance layer (Bronze/Silver/Gold)
  that prevents the "data swamp" failure mode
- **Schema-on-read for Bronze, schema-on-write for Gold**: Bronze accepts any
  payload (flexibility); Gold enforces strict schemas (correctness)

The lakehouse is why Yagye can run serious analytics without paying for Snowflake.

### Delta Lake

Delta Lake (and its equivalents: Apache Iceberg, Apache Hudi) adds ACID
transactions to a Parquet data lake:

- Atomic writes (no partial file updates)
- Time travel (query the lake as it was yesterday)
- Schema enforcement (rejected writes that violate the schema)
- Merge support (`MERGE INTO` for upserts on Parquet)

**Why Yagye does not use Delta Lake yet:**
DuckDB's read-from-S3 model does not require Delta Lake's transaction log.
Yagye's ETL pattern is append-only (new partitions per time window) — it does
not need upserts or time travel. Adding Delta Lake would require either the
Delta Spark runtime (heavy JVM dependency) or the `delta-rs` library.

**When to adopt:**
If Yagye needs time travel for data correction without full reprocessing, or
if SCD Type 2 upserts become complex enough that append-only partitions are
insufficient, Delta Lake (via `delta-rs`, which is DuckDB-compatible) is the
natural next step. This is a Phase 22+ consideration.

---

## 30. Data Maturity Levels

Data maturity models describe where an organisation sits in its data capability
journey. Understanding this helps the team set realistic expectations and make
the right architectural choices for their current level.

### The five levels

**Level 1 — Ad hoc (data is an afterthought)**

- Queries run directly against the production database by engineers
- Reports are hand-crafted SQL in spreadsheets
- No reproducibility: the same report run twice may give different answers
- No governance: anyone with DB credentials can access anything

*Yagye at P0–P5:* This was Yagye before any data platform work. Engineers
queried core_db directly for one-off analyses.

**Level 2 — Reactive (data infrastructure exists but is fragile)**

- A basic ETL pipeline copies data to a separate database or CSV files
- Reports exist but are not scheduled; they are run on demand
- Pipelines break and nobody notices until someone complains about a stale report
- No testing, no lineage, no documentation

*Yagye's goal: skip this level entirely* — the medallion architecture and
pipeline tests described in this document are designed to land at Level 3
from day one of the data platform.

**Level 3 — Proactive (data is reliable and governed)**

- Medallion architecture: Bronze/Silver/Gold with documented contracts
- Scheduled ETL with automated tests and alerting on failure
- Lineage: any Gold figure can be traced to its source
- PII governance: sensitive data is hashed/removed at Silver
- A small team can maintain the platform confidently

*Yagye's target at P20 data platform launch:* The architecture described in
this document — DuckDB, Parquet on S3, Redpanda Connect, medallion medallion
structure, SCD Type 2, lineage metadata — is explicitly designed to reach
Level 3 at first deployment.

**Level 4 — Differentiating (data drives product decisions)**

- ML models in production (routing predictor, risk scorer) using Gold features
- A/B testing infrastructure: data determines which product changes ship
- LLM enrichment and text-to-SQL make data accessible to non-engineers
- The data platform is a competitive advantage, not a cost centre

*Yagye's target at P22+:* The ML architecture (separate document) + the AI
layers described in §§26–28 above.

**Level 5 — Transformative (data is the product)**

- External data products: Yagye's transaction data becomes a service sold to
  third parties (market intelligence, industry benchmarks)
- Real-time ML: models score every transaction in < 10ms using streaming feature
  stores
- Automated decision-making: routing, risk, and reserve decisions are fully
  automated with human-in-the-loop only for edge cases

*Yagye's long-term horizon:* This is the merchant analytics API — selling
anonymised market intelligence to enterprise merchants and financial institutions.
It requires Data Mesh patterns, federated governance, and external data contracts.
Relevant no earlier than P25+.

### Where Yagye is today (2026-10)

```
Level 1 ──── Level 2 ──── Level 3 ──── Level 4 ──── Level 5
                              ▲
                         Target at P20
                         (data platform
                          first deploy)
```

The architecture decisions made now (medallion, SCD Type 2, lineage, pipeline
tests) are the foundation that makes Level 4 reachable at P22. Cutting corners
at Level 3 — skipping SCD, skipping lineage, skipping tests — creates a debt
that makes Level 4 ML features unreliable (garbage in, garbage out).

---

## 24. Data Lineage

### What it is and why it matters for a PSP

Data lineage is the ability to trace any number in a report or model back to
the raw source event that produced it. For Yagye this is both a correctness
requirement and a compliance requirement. A regulator asking "show me the
source for this GHS 4,200 fee total in the August BoG report" must be
answerable without guesswork.

### Yagye's lineage chain

The outbox `event_id` is a UUIDv7 generated at Core write time. It flows
through every layer unchanged:

```
Core transaction
   └─ outbox_messages.event_id = "018e4a2c-..."    ← generated at write
         │
         │ Redpanda Connect writes to Bronze
         ▼
Bronze/raw/2026/10/18/payments.parquet
   └─ event_id = "018e4a2c-..."                    ← preserved exactly

         │ DuckDB Silver ETL deduplicates on event_id
         ▼
Silver/payments/2026/10/payments_silver.parquet
   └─ event_id = "018e4a2c-..."                    ← dedup key, preserved

         │ DuckDB Gold ETL joins Silver → fact table
         ▼
Gold/payments_mart/fact_payments.parquet
   └─ source_event_id = "018e4a2c-..."             ← FK back to Bronze event
```

Because Bronze is append-only and the `event_id` is immutable (a UUIDv7 from
Core — nothing downstream generates or modifies it), the chain is always
traceable.

### The lineage query

To trace a Gold fact row back to its raw event:

```sql
-- Given a fact_payments row with source_event_id = '018e4a2c-...'
SELECT b.*
FROM read_parquet('s3://yagye-lake-raw/payments/**/*.parquet') b
WHERE b.event_id = '018e4a2c-...'
```

This returns the original raw Bronze payload exactly as Redpanda Connect
wrote it — the verbatim outbox message from Core. From there, the `merchant_id`
and `payment_id` in the payload link back to the Core write model for the
authoritative state.

### Derived metrics and ML lineage

Derived metrics (e.g. a 7-day rolling success rate) do not map to a single
source event — they span a time window. Their lineage is:
- The ETL job version (Git SHA recorded in `training_metadata.json`)
- The Bronze partition window read (e.g. `2026-08-01` to `2026-08-31`)
- The DuckDB SQL transform that produced the metric

The `training_metadata.json` in the model registry (see `ml-architecture.md`
§6) records the exact Bronze partition window for each training run. That is
the lineage for ML features — any model score can be traced back to the
training data window that produced the model weights.

### Tooling plan

At current scale (< 10 Gold tables), the `source_event_id` column on Gold
fact tables provides sufficient lineage for regulatory audits. The lineage
query above is the audit tool.

When Gold tables exceed 10, a lightweight lineage graph will be added:
- A `lineage_graph` DuckDB table recording: `job_name`, `git_sha`,
  `input_partitions[]`, `output_table`, `run_at`
- Populated by each ETL job at completion
- Queryable: "which jobs wrote to `fact_payments` between Aug 1 and Aug 31
  and what Bronze partitions did they read?"

**Target standard: OpenLineage** — a vendor-neutral lineage format compatible
with Marquez and Grafana's lineage view. Emitting OpenLineage events from
Oban ETL jobs is a < 1-day addition when the time comes.

---

## 25. Pipeline Testing and Data Quality

Three testing layers, each with a different cadence and scope.

### Layer 1 — Unit tests on DuckDB SQL transforms

**Cadence:** CI on every PR.  
**What it tests:** The SQL logic of each ETL step in isolation.

Each ETL script has a paired pytest file that:
1. Writes a small Parquet fixture (3–5 rows) to a temp directory
2. Runs the transform SQL against the fixture via DuckDB in-process
3. Asserts the output matches expected rows exactly

```python
# tests/data_engineering/test_silver_payment_dedup.py
def test_payment_silver_dedup(tmp_path):
    """Two rows with the same event_id — exactly one should survive."""
    bronze = pd.DataFrame([
        {"event_id": "018e4a2c-a", "state": "succeeded", "amount_minor": 10000,
         "inserted_at": "2026-10-18T10:00:00"},
        {"event_id": "018e4a2c-a", "state": "succeeded", "amount_minor": 10000,
         "inserted_at": "2026-10-18T10:00:01"},  # duplicate, later timestamp
    ])
    bronze.to_parquet(tmp_path / "bronze.parquet")

    result = duckdb.execute("""
        SELECT DISTINCT ON (event_id) *
        FROM read_parquet(?)
        ORDER BY event_id, inserted_at DESC
    """, [str(tmp_path / "bronze.parquet")]).df()

    assert len(result) == 1
    assert result.iloc[0]["inserted_at"] == "2026-10-18T10:00:01"
```

Coverage target: every Silver and Gold transform has at least one happy-path
test and one edge-case test (empty input, duplicate event_id, null required
field).

### Layer 2 — Data quality checks after each ETL job

**Cadence:** After every ETL job run (daily for batch jobs, per-batch for
streaming).  
**What it tests:** The output data meets its contract before downstream jobs
consume it. Any failure halts the pipeline and fires an alert.

```python
def run_dq_checks(conn: duckdb.DuckDBPyConnection, table: str):
    """Run all DQ checks for a given table. Raise on first failure."""
    assert_no_nulls(conn, table, required_columns[table])
    assert_no_duplicate_event_ids(conn, table)
    assert_row_count_within_bounds(conn, table, yesterday_count, tolerance=0.20)
    if table in referential_integrity_checks:
        assert_referential_integrity(conn, table)
    if table.startswith("dim_"):
        assert_scd_no_gaps(conn, table)

def assert_no_nulls(conn, table, columns):
    for col in columns:
        n = conn.execute(
            f"SELECT COUNT(*) FROM {table} WHERE {col} IS NULL"
        ).fetchone()[0]
        assert n == 0, f"NULL violation: {table}.{col} has {n} null rows"

def assert_scd_no_gaps(conn, table):
    """Every (merchant_id, provider_id) must have exactly one open row."""
    n = conn.execute(f"""
        SELECT COUNT(*) FROM (
            SELECT merchant_id, provider_id, COUNT(*) AS open_rows
            FROM {table}
            WHERE valid_to = '9999-12-31'
            GROUP BY merchant_id, provider_id
            HAVING COUNT(*) != 1
        )
    """).fetchone()[0]
    assert n == 0, f"SCD gap in {table}: {n} (merchant_id, provider_id) pairs have ≠1 open row"
```

Full DQ check catalogue:

| Check | Tables | Assertion |
|---|---|---|
| No nulls on required columns | Silver+, Gold | `amount_minor`, `event_id`, `merchant_id` never null |
| No duplicate `event_id` | Silver | 0 duplicates on primary dedup key |
| Row count within bounds | Silver | ±20% of yesterday's count (catches ingestion gaps) |
| Referential integrity | Gold fact → dim | Every `fact_payments.merchant_id` exists in `dim_merchants` |
| Sum-zero assertion | Gold ledger | For any `ledger_entry_id`, SUM(debits) = SUM(credits) |
| SCD gap check | Gold dim tables | Each entity has exactly one row with `valid_to = '9999-12-31'` |
| Freshness check | Silver, Gold | Latest `event_at` in Silver not more than 2h behind `NOW()` |

### Layer 3 — End-to-end smoke tests (nightly, against Floci)

**Cadence:** Nightly at 02:00.  
**What it tests:** The full pipeline from Core API call to Gold fact row.

The test:
1. Fires 10 synthetic payments through Core (simulation mode, deterministic
   MSISDNs so outcomes are known)
2. Waits for the outbox relay to publish the events
3. Asserts events appear in Bronze within 60 seconds
4. Asserts Silver dedup completes within 5 minutes
5. Asserts Gold fact rows appear within 15 minutes with correct `amount_minor`
   and `fee_minor` matching what Core computed

Because the MSISDNs are deterministic (`024 100 0001` = success, `024 100 0002`
= insufficient_funds), the expected Gold outcomes are known before the test
runs. Any deviation is a pipeline regression.

This test runs against Floci (not real AWS) so it is cheap and safe to run
nightly. It is the only test that exercises Redpanda Connect, the Oban ETL
jobs, and DuckDB S3 reads together.

---

## 26. AI Layer 1 — LLM Enrichment

See `docs/data-engineering/ai-layer.md` §1 for full detail.

**Summary:** Free-text fields (dispute reason text, invoice line item
descriptions, KYB application notes) are enriched with LLM-generated
categories as a Silver ETL step. The categories become features in the ML
risk scorer and reserve recommender. Enrichment uses `claude-haiku-5-5`
(cheapest capable model), batched at 50 rows per API call, with result
caching in the Silver table to avoid re-calling the LLM for unchanged text.

---

## 27. AI Layer 2 — RAG Chatbot on Analytics Data

See `docs/data-engineering/ai-layer.md` §2 for full detail.

**Summary:** Ops analysts query Yagye's Gold data in natural language via
a portal interface. The question is sent to Core, which builds a text-to-SQL
prompt using the Gold schema as context, calls `claude-sonnet-5-5` to generate
SQL, validates the SQL (read-only, Gold tables only, `mode = 'live'`
enforced), executes it via DuckDB, and returns the result with the SQL shown
for audit. DuckDB is used instead of a vector database because analytical
queries require exact numerical operations that embedding similarity cannot
handle.

---

## 28. AI Layer 3 — Text-to-SQL for Merchants

See `docs/data-engineering/ai-layer.md` §3 for full detail.

**Summary:** Merchant portal users type natural language questions about
their own payment data. Same text-to-SQL pipeline as the ops chatbot, with
`merchant_code = current_user.merchant_code` injected into every query by
the SQL validator — structurally impossible to bypass. Merchants can query
`fact_payments`, `dim_providers`, and `dim_pricing_rules` scoped to their
own data only.

---

## 29. Data Architecture Evolution and Where Yagye Sits

Every data platform evolves through recognisable stages as the business
grows. Knowing where Yagye sits now — and what triggers the next stage —
prevents premature over-engineering and under-investing at the same time.

### Stage 1 — Operational reports from the write DB (pre-Yagye)

Most startups begin here: analytics queries run directly on the PostgreSQL
write DB. This works at small scale. It breaks when:
- A slow GROUP BY query locks a row that a payment is trying to update
- The analytics query plan degrades as the table grows past 10M rows
- A data scientist needs 90-day rolling windows across three tables

Yagye skipped this stage deliberately. The data platform was designed before
production traffic existed.

### Stage 2 — Read replica + simple ETL (where Yagye is today)

The operational databases are OLTP. The data platform (Redpanda → Bronze
Parquet → Silver → Gold → DuckDB) is OLAP. They share nothing except the
outbox event stream. This is the right architecture for Yagye's current scale.

Characteristics of Stage 2:
- One centralized data platform serving all consumers (ML, ops, analytics)
- DuckDB as the sole query engine (single-process, no distributed compute)
- Batch ETL jobs (daily for Gold, near-real-time for Silver via Redpanda Connect)
- Schema-first data contracts (Parquet schemas, SCD Type 2, lineage via event_id)

### Stage 3 — Distributed query engine (trigger: Gold table query > 60s)

When individual DuckDB ETL jobs take more than 60 seconds or individual
analyst queries time out, it is time to add a distributed query engine.

Target: **Trino** (formerly PrestoSQL) or **AWS Athena** (Trino-compatible,
managed). Both query Parquet on S3 directly — no data migration. The DuckDB
ETL SQL runs unchanged on Trino (standard SQL).

Trino adds: parallel query execution across multiple workers, cost-based
optimiser for star schema joins, concurrent user isolation.

### Stage 4 — Data Mesh (trigger: > 3 autonomous engineering teams)

When separate product teams (Payments, Risk, Ops) each own their data domain
and have conflicting SLA requirements, a centralized platform becomes a
bottleneck. Each domain publishes its own Gold data products, defines its own
SLAs, and is responsible for its own DQ checks. A data mesh governance layer
(federated catalogue, shared data contract standards) prevents fragmentation.

Yagye does not need Data Mesh today. The mart-based partition within the
centralized platform (§20) provides domain clarity without federated
governance overhead.

---

## 30. Data Maturity Levels

A practical self-assessment framework. Yagye's current position and the
next milestone per dimension:

| Dimension | Level 1 | Level 2 (today) | Level 3 (next) | Level 4 |
|---|---|---|---|---|
| **Storage** | Write DB only | Lakehouse (Bronze/Silver/Gold) | Iceberg/Delta for ACID | Multi-region lakehouse |
| **Ingestion** | Manual exports | Outbox → Redpanda Connect | CDC + schema registry | Real-time streaming |
| **Processing** | SQL on write DB | DuckDB batch ETL | Trino / Athena | Flink stateful streaming |
| **Orchestration** | Cron scripts | Oban ETL jobs | dbt + Dagster | Multi-team pipelines |
| **Quality** | None | DQ checks + CI unit tests | Great Expectations | Data contracts + SLOs |
| **Lineage** | None | `source_event_id` column | OpenLineage graph | Full impact analysis |
| **ML** | No ML | Batch-trained ONNX models | Online learning | Causal ML |
| **AI** | No AI | LLM enrichment (Silver) | RAG + text-to-SQL | Autonomous agents |
| **Governance** | None | Centralized + role-based | Data catalogue | Federated mesh |

**Yagye's honest position:** solidly Level 2 across all dimensions, with
Level 3 roadmapped for storage (Iceberg when needed), orchestration (dbt
trigger at 20 models), quality (Great Expectations if DQ check count exceeds
20), and lineage (OpenLineage at 10+ Gold tables).

The AI and ML rows are the most advanced relative to Yagye's operational
maturity — a deliberate choice, because routing optimisation and risk scoring
have direct revenue and loss-prevention impact at small transaction volumes,
not just at scale.
