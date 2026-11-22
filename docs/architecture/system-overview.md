# System Overview

**Last updated:** 2026-11-22

This document describes the Yagye platform at the component level: what each
service is, what it owns, and how the pieces connect. Read this before any
other architecture document.

---

## What Yagye is

Yagye is a **Payment Service Provider (PSP)** built for the West African market.
In Model A (current), Yagye is the PSP — it holds float accounts, KYBs merchants,
and routes payments through its own provider network. In Model B (P22+), Yagye
additionally acts as an orchestration layer for large enterprise merchants who
want to route across their own provider contracts.

---

## Component topology

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                               External World                                  │
│   Merchant API clients     Merchant / ops users     PSP Providers             │
│   (REST integrations)      (browser, any role)      (MTN MoMo, Stripe, …)    │
└──────────┬─────────────────────────┬──────────────────────────┬──────────────┘
           │ HTTPS                   │ HTTPS                    │ HTTPS
           ▼                         ▼                          ▼
┌──────────────────────┐   ┌─────────────────────┐   ┌────────────────────────┐
│    yagye_core         │   │    yagye_portal      │   │  Provider webhook      │
│    (Elixir / Phoenix) │◄──┤    (Rails 8 + Phlex) │   │  ingestion             │
│                       │   │                     │   │  POST /provider-       │
│  /v1  — merchant API  │──►│  Merchant dashboard  │   │    webhooks/:code      │
│  /internal — ops API  │   │  Ops/compliance UI   │   └────────────────────────┘
│  /provider-webhooks   │   │  Karafka consumer    │
│                       │   │  Solid Queue         │
│  Oban workers         │   │  Solid Cable         │
│  Double-entry ledger  │   └──────────┬───────────┘
│  Transactional outbox │              │ SQL
│  Routing + risk engine│              ▼
│  ML scoring client    │   ┌──────────────────────┐
└───────┬───────────────┘   │  portal_db            │
        │ SQL               │  (PostgreSQL)         │
        ▼                   └──────────────────────┘
┌──────────────────────┐
│  core_db              │
│  (PostgreSQL)         │
│                       │
│  Oban jobs table      │
│  outbox_messages      │
│  idempotency_keys     │
└──────────────────────┘
```

### Event-driven layer

```
yagye_core
  │
  ├─ OutboxRelayWorker (Oban) ──────────────► Redpanda (event bus, :9092)
  │                                                │ Karafka consumers
  │                                                └──────────────────► yagye_portal
  │                                                                     (real-time UI events)
  │
  ├─ DataLakeIngestionWorker (Oban, 1-min) ───────► S3 / Floci
  │   polls outbox_messages, writes Bronze NDJSON   (yagye-lake-raw/)
  │
  └─ WebhookDeliveryWorker (Oban) ─────────────── RabbitMQ
      Broadway consumer per merchant endpoint       per-merchant queues + DLX
```

### Data & ML layer

```
S3 / Floci
  yagye-lake-raw/   (Bronze: NDJSON, 1-min cadence)
        │ DuckDB ETL (hourly)
        ▼
  yagye-lake-silver/ (Silver: typed Parquet, deduplicated)
        │ DuckDB ETL (every 6h)
        ▼
  yagye-lake-gold/   (Gold: aggregates — payments_daily, provider_health_hourly,
                      risk_features_hourly, merchant_features_weekly)
        │ weekly export
        ▼
  yagye-ml-models/   (ONNX training snapshots)

All ETL above runs in yagye_data (Python + DuckDB service).

yagye_core (Oban workers) ──► Redis
  ProviderHealthWorker (2-min):   yagye:features:provider:{code}
  CustomerRiskWorker (5-min):     yagye:features:customer:{msisdn_hash}
  MerchantRiskWorker (5-min):     yagye:features:merchant:{merchant_id}

yagye_core PaymentDispatchWorker ──HTTP 200ms──► yagye_scoring (FastAPI)
  /score/routing  → routing predictor (XGBoost / ONNX)
  /score/risk     → risk scorer (shadow mode: log only; active: block / review)
  /score/reserve  → reserve recommender
  /score/churn    → churn predictor

  yagye_scoring reads: Redis (real-time features) + Gold Parquet (batch features)
  yagye_scoring uses:  Anthropic Claude for LLM enrichment on risk decisions
                        MLflow for experiment tracking
```

### Observability stack

```
All services ──OTLP + bearer token──► Grafana Alloy  ◄── Docker log tail
Blackbox exporter ◄── Alloy scrape ──► /up / /health probes
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
                  Tempo       Loki    Prometheus
               (S3/Floci    (Docker    (metrics +
                backend)     logs)     remote_write)
                     └──────────┼──────────┘
                                ▼
                            Grafana ──► Alertmanager ──► email (Mailpit in dev)

Side exporters scraped by Alloy:
  cAdvisor         → per-container CPU / RAM / network
  Node Exporter    → host CPU / RAM / disk
  Postgres Exporter → pg_stat_activity, replication lag, dead tuples, WAL
  Redis Exporter   → memory, hit rate, evictions
  Redpanda         → /public_metrics (native, low-cardinality)
  RabbitMQ         → rabbitmq_prometheus plugin (:15692)
```

### Local dev only

```
┌──────────────────────────────────────────────┐
│  gateway_simulator  (Elixir / Phoenix)        │
│  dev + CI only — never deployed to prod       │
│                                              │
│  Deterministic MSISDN → outcome mapping:     │
│    024 100 0001 → success                    │
│    024 100 0002 → insufficient_funds         │
│    024 100 0003 → timeout                    │
└──────────────────────────────────────────────┘
┌──────────────────────────────────────────────┐
│  Floci  (LocalStack-compatible S3 emulator)  │
│  Buckets: yagye-lake-raw, yagye-lake-silver, │
│    yagye-lake-gold, yagye-ml-models,         │
│    yagye-kyb-docs, tempo-traces              │
└──────────────────────────────────────────────┘
┌──────────────────────────────────────────────┐
│  Mailpit  (SMTP sink, port 8025)             │
│  Catches all Alertmanager alert emails       │
└──────────────────────────────────────────────┘
```

---

## yagye_core

**Language / framework:** Elixir 1.17 + Phoenix 1.7 + Ecto 3
**Database:** PostgreSQL (core_db)
**Background jobs:** Oban (PostgreSQL-backed)
**Observability:** OpenTelemetry (traces + metrics) + logger_json (structured logs)

### What it owns

- The authoritative write model for every financial entity: payments, merchants,
  customers, invoices, disputes, refunds, payouts, settlements, ledger entries.
- The double-entry ledger — the only place where money is moved.
- All routing logic (platform-global rules + merchant-scope overrides at P16).
- Provider dispatch, retry, and circuit-breaking.
- Provider webhook ingestion (HMAC-verified per provider).
- The transactional outbox — every domain state change publishes an event row
  in the same DB transaction that mutates the entity.
- Real-time ML feature writers: `ProviderHealthWorker`, `CustomerRiskWorker`,
  `MerchantRiskWorker` write Redis keys consumed by `yagye_scoring`.
- The `ScoringClient` calling `yagye_scoring` for routing and risk decisions.

### API surfaces

| Surface | Pipeline | Auth | Purpose |
|---|---|---|---|
| `POST /v1/*` | `:v1` | Bearer API key | Merchant-facing write operations |
| `GET /v1/*` | `:v1` | Bearer API key | Merchant-facing read operations |
| `POST /internal/*` | `:internal` | X-Service-Token | Portal → core ops |
| `GET /internal/*` | `:internal` | X-Service-Token | Portal read projections |
| `POST /provider-webhooks/:code` | `:provider_webhooks` | HMAC per provider | Inbound provider callbacks |
| `GET /metrics` | — | None (firewall-gated) | Prometheus scrape |
| `GET /api/openapi` | `:api` | None | OpenAPI spec |

### Key internal boundaries

Module exports are declared in `YagyeCore` (`lib/yagye_core.ex`). The web layer
(`YagyeCoreWeb`) may only reference modules listed in that export. This prevents
controllers from bypassing context functions to touch schemas directly.

---

## yagye_portal

**Language / framework:** Ruby 3.3 + Rails 8.1 + Phlex (custom, no PhlexUI)
**Database:** PostgreSQL (portal_db — separate from core_db)
**Background jobs:** Solid Queue
**Real-time:** Solid Cable (PostgreSQL LISTEN/NOTIFY)
**Event consumption:** Karafka (consuming Redpanda topics: payment events, webhook delivery)
**CSS / JS:** Tailwind CSS + Vite + ECharts
**Auth:** Devise + TOTP (P13); Passkeys (P13.5); SSO (P14)
**Authorisation:** Pundit + DB-backed RBAC (8 roles, 21 permissions)
**Observability:** OpenTelemetry (traces via OTLP) + structured JSON request logs

### What it owns

- A read-model projection of core data: `Payment`, `PortalMerchantApplication`,
  `PortalWebhookEndpoint`, `PortalWebhookDelivery`, `RiskCase`.
- User identity, authentication, and sessions.
- Dynamic DB-backed RBAC enforced by Pundit policies.
- The ops-facing UI for Yagye internal staff (compliance, analyst, manager roles).
- The merchant-facing dashboard (owner, finance, developer, support roles).
- Risk & Compliance section: flagged payments, SAR export, disposition workflow.

### What it does NOT own

- The write model. Portal never writes financial records to core_db.
- Provider credentials or routing configuration directly — calls `/internal/*` on core.
- Ledger entries, balances — it reads projections (`proj_merchant_balances`).

### Portal → core communication

Portal calls core's `/internal` endpoints via `X-Service-Token`. This is the
only allowed direction for financial writes. Portal never touches core_db directly.

Redpanda → Karafka → Portal is the read direction for real-time event projection.

---

## yagye_data

**Language:** Python 3.12
**Query engine:** DuckDB (embedded, in-process)
**Storage:** S3 / Floci (Bronze, Silver, Gold, ML models buckets)
**Deployment:** `yagye_data` docker-compose service; ETL jobs run on cron schedule

### What it owns

- Bronze → Silver ETL (hourly): reads NDJSON from `yagye-lake-raw/`, validates,
  deduplicates on `event_id`, writes typed Parquet to `yagye-lake-silver/`.
- Silver → Gold ETL (every 6h): builds `payments_daily`, `provider_health_hourly`,
  `risk_features_hourly`, `merchant_features_weekly` aggregates.
- ML training dataset export (weekly): `routing_predictor` and `risk_scorer`
  training snapshots in `yagye-lake-gold/ml_training/`.
- DuckDB query layer for BoG regulatory reports.

### What it does NOT own

- Real-time features — those are written by Core's Oban workers into Redis.
- Model serving — `yagye_scoring` owns that.

### Medallion layers

```
Bronze  yagye-lake-raw/     — NDJSON, written by DataLakeIngestionWorker (Core)
Silver  yagye-lake-silver/  — Parquet (Zstd), deduplicated, typed, UTC-normalised
Gold    yagye-lake-gold/    — Parquet (Zstd), pre-aggregated, PII-hashed
```

---

## yagye_scoring

**Language:** Python 3.12 + FastAPI
**Models:** XGBoost / LightGBM → ONNX; loaded from `yagye-ml-models/` on startup
**Feature store:** Redis (real-time, written by Core workers) + Gold Parquet (batch)
**LLM enrichment:** Anthropic Claude (risk context summaries; shadow mode default)
**Experiment tracking:** MLflow
**Observability:** OpenTelemetry + OpenLIT (LLM-specific: tokens, cost, latency)

### Endpoints

| Endpoint | Model | Called by |
|---|---|---|
| `POST /score/routing` | Routing predictor | `PaymentDispatchWorker` (shadow default) |
| `POST /score/risk` | Risk scorer | `create_payment` path (shadow default) |
| `POST /score/reserve` | Reserve recommender | Manual invocation (P20+) |
| `POST /score/churn` | Churn predictor | Scheduled batch (P20+) |

### Shadow vs active mode

| Env var | Default | Behaviour |
|---|---|---|
| `RISK_ML_ENABLED` | `false` | Shadow: score, log, don't block |
| `ROUTING_ML_ROLLOUT_PERCENT` | `0` | Shadow: score, log, keep rule-based ordering |

Core's `ScoringClient` has a 200ms timeout. On timeout or connection error it
returns `{:error, :scoring_unavailable}` and Core proceeds without ML input.

---

## gateway_simulator

**Language / framework:** Elixir + Phoenix
**Database:** None (stateless; SQLite for session state if needed in CI)
**Deployment:** Development and CI only — never in production

The anti-corruption layer (ADR-0013) that stands in for real PSP providers.
It speaks the same HTTP protocol as real providers so Core's provider adapters
are tested against real HTTP semantics without sandbox credentials.

Outcome control via fixed MSISDN prefixes and `X-Simulator-Outcome` headers:

```
024 100 0001 → success
024 100 0002 → insufficient_funds
024 100 0003 → timeout
024 100 0004 → expired
024 100 0005 → not_registered
```

---

## Infrastructure dependencies

| Component | Purpose | Status |
|---|---|---|
| PostgreSQL | core_db + portal_db; Oban; outbox; idempotency | Live |
| Redpanda | Event bus: Core outbox → Portal Karafka consumers | Live (P14) |
| Redis | Real-time ML feature store; distributed rate-limiting | Live (P17) |
| RabbitMQ | Outbound merchant webhooks (Broadway, per-merchant queues + DLX) | Live (P15) |
| Floci | Local S3 emulator: data lake, Tempo traces, KYB docs (dev/CI) | Live (dev) |
| AWS S3 | Data lake + KYB documents (production) | P22 |
| AWS KMS | KYB document encryption (production) | P22 |
| MTN MoMo API | Mobile money provider | Live (P1) |
| Stripe | Card provider | Live (P13) |
| Flutterwave | Alternative provider | Live (P13) |
| Paystack | Alternative provider | Live (P13) |
| Twilio / SMS | SMS notifications for OTP, payment receipts | P18 |

### Observability infrastructure

| Component | Purpose | Port |
|---|---|---|
| Grafana Alloy | Single OTLP receiver + log tailer + Prometheus scraper | 4317 (gRPC), 4318 (HTTP) |
| Loki | Log storage and LogQL queries | 3100 |
| Tempo | Trace storage (backed by S3/Floci) with TraceQL | 3200 |
| Prometheus | Metrics storage, SLOs, alert rules | 9090 |
| Grafana | Dashboards and alert management UI | 3000 |
| Alertmanager | Alert routing by severity label (email via Mailpit in dev) | 9093 |
| Blackbox Exporter | HTTP health probes for services without native /metrics | 9115 |
| cAdvisor | Per-container CPU/RAM/network metrics | 8080 |
| Node Exporter | Host CPU/RAM/disk metrics | 9100 |
| Postgres Exporter | pg_stat_activity, replication, bloat metrics | 9187 |
| Redis Exporter | Redis memory, hit rate, eviction metrics | 9121 |
| Mailpit | SMTP sink for local alert email testing | 8025 |

---

## Database separation

core_db and portal_db are separate PostgreSQL databases (and in production,
separate instances). This is deliberate:

- **Isolation:** A slow portal reporting query cannot lock core write transactions.
- **Security:** Portal credentials cannot touch the ledger or payment tables directly.
- **Scaling:** Different load profiles — core is write-heavy; portal is read-heavy.
- **Read-model freedom:** Portal schema is denormalised for reads and does not
  mirror core's normalised write model.

The two databases are kept consistent by the outbox → projection pipeline
(ADR-0015). Projections are eventually consistent. Core is the system of record;
portal projections are derived.

---

## Mode isolation

Every domain record in both databases carries a `mode` column:
`simulation | sandbox | live`.

- `simulation` — fully in-process, no real provider calls. All providers route
  to gateway_simulator. Used for development and merchant testing.
- `sandbox` — real provider sandbox/test accounts. Safe for integration testing.
- `live` — real money, real provider accounts.

The `:v1` pipeline's `VerifyMode` plug enforces that a request's API key mode
matches the resource mode. Cross-mode reads are blocked at the API layer.
The `mode` column on every DB row enables auditors to query without ambiguity.

---

## Security model

| Layer | Mechanism |
|---|---|
| Merchant API auth | Bearer token (API key), mode-aware (ADR-0011) |
| Internal (portal → core) | X-Service-Token shared secret, firewall-gated |
| OTLP ingestion | Bearer token auth on Alloy receiver (env: OTLP_BEARER_TOKEN) |
| Provider webhook auth | HMAC-SHA256 per provider, verified in controller |
| Portal session | Devise (email+password+TOTP), session token in PostgreSQL |
| Portal authorisation | Pundit policies + DB-backed RBAC (ADR-0017) |
| Segregation of duties | DB CHECK constraints + changeset enforcement |
| No hard deletes | ON DELETE RESTRICT on all domain FKs (ADR-0020) |
| Idempotency | DB-backed idempotency state machine (ADR-0008) |
| Risk screening | Shadow-mode ML block/review; SoD on case disposition |

---

## Further reading

| Document | What it covers |
|---|---|
| [engineering-concepts.md](engineering-concepts.md) | Why: idempotency, exactly-once processing, double-entry ledger, transactional outbox, event-driven design, mode isolation, security |
| [observability.md](observability.md) | Full observability stack: Alloy, Loki, Tempo, Prometheus, Grafana, alerting, PII rules |
| [payment-flow.md](payment-flow.md) | Step-by-step payment lifecycle from API call to ledger settlement |
| [data-flow.md](data-flow.md) | How data moves between Core, the outbox, Portal projections, and webhooks |
| [scaling-playbook.md](scaling-playbook.md) | How to scale each component under load |
| [api-conventions.md](api-conventions.md) | API design rules, error envelopes, pagination, versioning |
| [data-engineering/README.md](../data-engineering/README.md) | Data platform: lakehouse architecture, Floci, DuckDB ETL, medallion pipeline |
| [data-engineering/ml-architecture.md](../data-engineering/ml-architecture.md) | Four ML models: routing predictor, risk scorer, reserve recommender, churn predictor |
| [data-engineering/ai-layer.md](../data-engineering/ai-layer.md) | AI layer: LLM enrichment, ops RAG chatbot, merchant text-to-SQL |
| [roadmap/remaining-features.md](../roadmap/remaining-features.md) | Every deferred feature with prerequisites and implementation notes |
| [adr/README.md](../adr/README.md) | All 28 Architecture Decision Records |
