# Observability

**Last updated:** 2026-11-22

Yagye uses **OpenTelemetry** as the instrumentation layer and the **Grafana
OSS stack** (Alloy → Loki / Tempo / Prometheus / Grafana) for storage and
visualisation. See [ADR-0028](../adr/0028-opentelemetry-grafana-stack.md) for
the rationale behind these choices.

---

## Signals

| Signal | Backend | What it covers |
|--------|---------|----------------|
| **Traces** | Tempo | End-to-end request spans across Portal, Core, and PSP adapters |
| **Logs** | Loki | Structured JSON logs from every service; `trace_id` auto-links to Tempo |
| **Metrics** | Prometheus | SLOs, infrastructure health, queue depths, LLM usage |

Grafana is the single pane of glass. All three backends are provisioned as
datasources; the trace/log correlation derived field is configured to link
`trace_id` occurrences in Loki directly to the matching Tempo trace.

---

## Architecture

```
                    ┌──────────────────────────────────────────────────┐
                    │                 Grafana Alloy                      │
                    │                                                  │
                    │  ┌──────────────┐  ┌──────────┐  ┌───────────┐  │
Instrumented        │  │  OTLP recv   │  │  Docker  │  │Prometheus │  │
services ─OTLP──►  │  │  gRPC :4317  │  │  log     │  │  scrape   │  │
(bearer token)      │  │  HTTP :4318  │  │  tail    │  │           │  │
                    │  │  bearer auth │  └────┬─────┘  └─────┬─────┘  │
Blackbox ◄─scrape─  │  └──────┬───────┘       │              │        │
(HTTP probes)       │         │               │              │        │
                    └─────────┼───────────────┼──────────────┼────────┘
                              │               │              │
                    ┌─────────┼───────────────┼──────────────┼────────┐
                    │  Tail sampling (10s      │              │        │
                    │  window; 100% errors/    │              │        │
                    │  slow; 100% all in dev)  │              │        │
                    └─────────┼───────────────┼──────────────┼────────┘
                              │               │              │
                              ▼               ▼              ▼
                           Tempo            Loki        Prometheus
                        (S3: Floci)       (logs)        (metrics)
                              └───────────────┴──────────────┘
                                              │
                                          Grafana
                                        (port 3000)
                                              │
                                       Alertmanager
                                        (port 9093)
                                              │
                                    dev: Mailpit (port 8025)
                                    prod: PagerDuty / email
```

Alloy is the single ingestion point. All routing to the three backends happens
inside Alloy's River config (`infra/docker/alloy/config.alloy`).

---

## OTLP bearer token auth

Every service sending OTLP to Alloy must include an `Authorization` header:

```
Authorization: Bearer <OTLP_BEARER_TOKEN>
```

Alloy validates this via `otelcol.auth.bearer.otlp_server`. The token is
injected via the `OTLP_BEARER_TOKEN` environment variable (default:
`yagye_dev_otlp_token` in dev). Services that omit the header are rejected
at the receiver level before any data is processed.

In production, inject via secrets manager and rotate on the same schedule
as other service-to-service secrets.

---

## Tempo: trace storage

### Storage backend

| Environment | Backend |
|---|---|
| Local dev / CI | Floci S3 (`s3://tempo-traces/`) with `forcepathstyle: true`, `insecure: true` |
| Staging / Prod | AWS S3 (`s3://yagye-tempo-traces/`) with standard IAM credentials |

The `floci_init` service in docker-compose creates the `tempo-traces` bucket before
Tempo starts (via `condition: service_completed_successfully`).

Tempo config lives at `infra/docker/tempo/config.yaml`.

### Tail-based sampling

Alloy buffers trace spans for `decision_wait = 10s` before making a keep/drop
decision per trace. Policies are evaluated with OR logic (keep if any match):

| Policy | Rule |
|---|---|
| `sample_errors` | Keep 100% of traces containing an ERROR span |
| `sample_slow` | Keep 100% of traces whose root span exceeds 1000ms |
| `sample_pct` | Keep N% of all remaining traces (100% in dev; 10% in staging/prod) |

The 100% rate in local dev ensures every page visit appears in Tempo immediately.
Lower this to 10% (or less) before deploying to staging/production to control
Tempo storage costs.

---

## Service instrumentation

### Portal (Rails)

Gems: `opentelemetry-sdk`, `opentelemetry-exporter-otlp`,
`opentelemetry-instrumentation-all`.

The `-all` gem activates auto-instrumentation for Rails, ActiveRecord, Rack,
Faraday, Redis, and Logger. The Faraday instrumentation is the critical piece:
every HTTP call made by `CoreApiClient` automatically receives a W3C
`traceparent` header, connecting Portal and Core traces into a single end-to-end
span tree with no code changes required in `CoreApiClient`.

Initialiser: `config/initializers/opentelemetry.rb`. Endpoint and propagator
are configured via `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_PROPAGATORS`
environment variables.

Request-level structured JSON logging: `config/initializers/request_logging.rb`
wraps every controller action to emit a JSON log line with `method`, `path`,
`status`, `duration_ms`, `trace_id`, and `request_id`. The `trace_id` is sourced
from `CorrelationId.current` which reads the OTel context.

### Core (Elixir)

Packages:

| Package | Spans for |
|---------|-----------|
| `opentelemetry_phoenix` | HTTP request/response |
| `opentelemetry_ecto` | DB queries (all Repo calls) |
| `opentelemetry_oban` | Background jobs (settlement, dispatch, recon, data lake) |
| `opentelemetry_finch` | PSP adapter HTTP calls |
| `opentelemetry_broadway` | Redpanda consumer pipelines |

Handlers are registered in `YagyeCore.Application.start/2`.

LLM calls to Anthropic (risk enrichment) are wrapped in manual spans using
OpenTelemetry semantic conventions for GenAI (`gen_ai.*` attributes).

### Scoring service (Python)

Auto-instrumented via `opentelemetry-distro` + `opentelemetry-bootstrap -a install`,
launched with `opentelemetry-instrument uvicorn …`.

**OpenLIT** (`openlit.init()`) adds LLM-specific observability on top of the
base OTel spans: Anthropic call latency, tokens in/out, model tier, estimated
cost per call. Data flows into Prometheus via Alloy.

---

## LLM observability

Two tools are used together because they solve different problems:

| Tool | Level | What it tracks |
|------|-------|----------------|
| **OpenLIT** | Infrastructure | Latency, tokens, cost, errors per API call |
| **Langfuse** (self-hosted) | Product | Conversation traces, prompt versions, eval scores, cost per session, feedback loop |

Langfuse runs as a separate service (`langfuse` in `docker-compose.yml`,
`:3200` locally, its own RDS database in production). The merchant AI chat UI's
thumbs-up/down feedback emits `langfuse.score` events (value `1` or `-1`),
turning user feedback into a time-series quality metric without a separate eval
pipeline.

OpenLIT metrics (`gen_ai_client_*`) are emitted by `yagye_scoring` and
`yagye_data` only — both are full-profile services. The LLM Grafana dashboard
shows "no data" in the basic stack (without `--profile full`); this is expected.

---

## Infrastructure metrics

| Component | Approach | Prometheus target |
|-----------|----------|-------------------|
| Core | Native via `PromEx` | `:4000/metrics` |
| Redpanda | Native | `:9644/public_metrics` (not `/metrics` — high cardinality) |
| RabbitMQ | `rabbitmq_prometheus` plugin | `:15692/metrics` |
| Redis | `redis_exporter` sidecar | `:9121/metrics` |
| PostgreSQL | `postgres_exporter` sidecar | `:9187/metrics` |
| Portal | Blackbox HTTP probe | `http://yagye_portal:80/up` via `/probe` |
| All containers | cAdvisor sidecar | `:8080/metrics` |
| Host OS | Node Exporter | `:9100/metrics` |

### Blackbox exporter (HTTP health probes)

Services without native `/metrics` endpoints (Portal in the basic stack) are
probed via blackbox exporter at `http://blackbox:9115/probe`. Alloy issues
probes every 15 seconds. The metric written is:

```
probe_success{job="blackbox", service="yagye_portal", instance="yagye_portal"} 1|0
```

When running the full profile (`--profile full`), add Simulator and Checkout
probes to the `prometheus.scrape "blackbox"` block in `alloy/config.alloy`.

### Prometheus remote write

All Alloy scraped metrics are pushed to Prometheus via
`prometheus.remote_write "default"` to `http://prometheus:9090/api/v1/write`.
Prometheus is configured with `--web.enable-lifecycle` to allow hot reloads of
alert rules via `POST /-/reload`.

---

## SLOs and alerts

Recording rules and alert rules live in:

```
infra/docker/prometheus/rules/slos.yml    # recording rules (5-min, 1-hour, 24-hour windows)
infra/docker/prometheus/rules/alerts.yml  # alert rules
infra/docker/prometheus/rules/dev_bootstrap.yml  # dev-only: suppress always-firing infra alerts
```

### Service health alerts

| Alert | Condition | Severity | Method |
|---|---|---|---|
| `CoreApiDown` | `up{job="yagye_core"} == 0` for 1m | critical | Native Prometheus scrape |
| `ScoringServiceDown` | `up{job="yagye_scoring"} == 0` for 2m | warning | Native Prometheus scrape |
| `ServiceDown` | `probe_success{job="blackbox"} == 0` for 1m | critical | Blackbox HTTP probe |

### Business SLO alerts

| Alert | Condition | Severity |
|---|---|---|
| `SettlementSweepMissing` | No sweep in > 4 hours | critical |
| `PaymentSuccessRateLow` | 5m success rate < 95% for 10m | critical |
| `PaymentSuccessRateWarning` | 5m success rate < 99% for 15m | warning |
| `PaymentApiHighLatency` | p99 latency > 2s for 5m | warning |
| `ReconciliationBreakSpike` | > 6 breaks in 30m | warning |
| `ObanJobDiscardRate` | > 1% discard rate in 1h | warning |

### PostgreSQL alerts

Six alerts covering: connection saturation (80%/95%), disk usage (80%/90%),
long-running transactions (> 30m), dead tuple ratio (> 10% per table), backup
staleness (> 25h), and replication lag (> 30s).

---

## Alert routing

Alertmanager routes by the `severity` label:

```
severity=critical → critical-email receiver → subject: "[CRITICAL] <alert> — Yagye PSP"
severity=warning  → warning-email receiver  → subject: "[WARNING] <alert> — Yagye PSP"
```

`inhibit_rules` suppresses any `warning` alert when a `critical` alert fires
for the same alertname + instance, preventing duplicate noise.

In development, all email is caught by **Mailpit** at `http://localhost:8025`.
No real SMTP credentials are needed for local alert testing.

---

## Dashboards

Dashboards are provisioned from `infra/docker/grafana/dashboards/`. The
following dashboards are planned or in-progress:

| Dashboard | Key panels |
|-----------|-----------|
| Risk & Fraud | Score histogram, disposition funnel, false-positive rate |
| PSP Health | Success rate / latency / error codes per provider |
| Settlement Pipeline | Batch age, stuck batches, net amounts by currency |
| Queue Health | Oban depth, RabbitMQ queue depths, Redpanda consumer lag |
| LLM Usage | Latency, tokens, cost/hour, Langfuse quality score trend (full profile only) |
| Infrastructure | DB connections, slow queries, Redis memory and hit rate |

---

## PII rules

The following data must **never** appear in any log, span attribute, or metric label:

- Customer MSISDN or phone number
- Card PAN or CVV
- Customer full name or email
- Merchant email
- API keys, OAuth tokens, or password hashes
- KYB document content

`db.statement` span attributes on queries touching `users`, `merchants`, and
`kyb_documents` are redacted by an `otelcol.processor.attributes` block in
Alloy's `config.alloy` before export.

Metric label cardinality must not include per-customer or per-merchant identifiers.
Allowed dimensions: `method`, `provider`, `currency`, `tier`.

Logs: `user_email` is explicitly excluded from all structured log output.

---

## Production deployment

### Local dev (Docker Compose)

Alloy runs as a container with the Docker socket mounted (`/var/run/docker.sock`)
for log collection. The River config is at `infra/docker/alloy/config.alloy`.

OTLP sender config per service:
```yaml
OTEL_EXPORTER_OTLP_ENDPOINT: http://alloy:4318
OTEL_EXPORTER_OTLP_HEADERS: "Authorization=Bearer ${OTLP_BEARER_TOKEN}"
OTEL_RESOURCE_ATTRIBUTES: service.name=<service>,deployment.environment=local
OTEL_PROPAGATORS: tracecontext,baggage
```

### AWS (P22)

Grafana Alloy runs as a **sidecar container** in each ECS task definition.
The sidecar receives OTLP on `localhost:4318` (intra-task networking) and
forwards to Grafana Cloud (or a self-hosted Grafana stack backed by S3 Tempo).

A standalone `observability-infra` ECS task runs Alloy to scrape the managed
infrastructure components (RDS, ElastiCache, AmazonMQ, MSK).

The local `config.alloy` and production `config.prod.alloy` Alloy configs
differ only in remote endpoint URLs and the `forcepathstyle`/`insecure` settings
for Tempo's S3 backend. No dashboards, alert rules, or SLO recording rules
change between environments.

Langfuse runs as its own ECS service backed by RDS PostgreSQL, accessible only
within the VPC.
