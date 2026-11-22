# ADR-0028: OpenTelemetry + Grafana Stack for Observability

**Date:** 2026-11-16
**Status:** Accepted

## Context

Yagye runs a polyglot stack across four runtimes (Elixir/Phoenix, Ruby/Rails,
Python/FastAPI, and JavaScript for Karafka consumers) plus infrastructure
components (PostgreSQL, Redis, RabbitMQ, Redpanda). It also embeds LLM calls
(Anthropic) in both the scoring service and the merchant AI chat.

As the platform approaches production, three observability problems need
solving:

1. **Blind spots**: Portal (Rails) emits no telemetry. Oban jobs, Finch HTTP
   calls, and Broadway pipelines in Core produce no spans. The scoring service
   emits nothing. Infrastructure components (Redpanda, RabbitMQ, Redis,
   Postgres) have no Prometheus scraping.

2. **Disconnected traces**: Core produces traces, but Portal → Core HTTP calls
   carry no `traceparent` header, so a request that originates in the browser
   appears as two separate traces with no link between them.

3. **LLM observability gap**: Anthropic API calls are made in both the scoring
   service and Core with no latency tracking, token counting, cost monitoring,
   or conversation-quality feedback loop.

Three observability stack approaches were considered:

**Option A — Datadog**: Fully managed, excellent auto-instrumentation, strong
Rails and Elixir agents. High per-host cost (~$23/host/month + log ingestion
fees) makes it expensive at PSP transaction volumes. Vendor lock-in on query
language (DQL) and dashboards.

**Option B — ELK Stack (Elasticsearch + Logstash + Kibana)**: Mature, strong
full-text search. Kibana lacks native trace UI. High operational burden
self-hosting Elasticsearch at scale. No native OTLP ingestion.

**Option C — OpenTelemetry + Grafana OSS stack (Alloy → Loki / Tempo /
Prometheus)**: OTel is the CNCF standard, vendor-neutral, with first-class
SDKs in Ruby, Elixir, and Python. Grafana OSS stack (Alloy, Loki, Tempo,
Prometheus) covers all three signals. Local dev runs identically to production;
migrating to Grafana Cloud for staging/production is a three-URL config swap
with no dashboard or alert-rule rewrites.

## Decision

We use **OpenTelemetry SDK + Grafana OSS stack**, with **Grafana Cloud** for
staging and production environments.

### Signal routing

```
Portal (Rails)   ──OTLP──▶ Alloy ──▶ Tempo   (traces)
Core (Elixir)    ──OTLP──▶ Alloy ──▶ Loki    (logs)
Scoring (Python) ──OTLP──▶ Alloy ──▶ Prometheus (metrics)
Karafka consumer ──OTLP──▶
                            Alloy ──▶ Grafana (dashboards + alerts)
```

### Per-runtime instrumentation

| Runtime | Key packages |
|---------|-------------|
| Rails (Portal) | `opentelemetry-sdk`, `opentelemetry-exporter-otlp`, `opentelemetry-instrumentation-all` |
| Elixir (Core) | existing SDK + `opentelemetry_oban`, `opentelemetry_finch`, `opentelemetry_broadway` |
| Python (Scoring) | `opentelemetry-distro`, `opentelemetry-exporter-otlp`, `openlit` |

### End-to-end trace propagation

`opentelemetry-instrumentation-all` includes `opentelemetry-instrumentation-faraday`.
Because `CoreApiClient` uses Faraday, the gem automatically injects the W3C
`traceparent` header into every Portal → Core HTTP call, joining the two trace
trees without code changes to `CoreApiClient`.

### LLM observability

Two complementary tools solve distinct problems:

- **OpenLIT** (scoring service, Python): infrastructure-level LLM metrics —
  latency, tokens in/out, cost per call, error rate. OTel-native; data flows
  to the existing Prometheus + Grafana stack. One-liner: `openlit.init()`.

- **Langfuse** (self-hosted): conversation-level tracing — prompt versions,
  eval scores, cost per session, replay. Connects the merchant AI chat
  thumbs-up/down feedback to measurable quality scores. Self-hosted keeps all
  conversation content inside Yagye's own infrastructure.

### Infrastructure metrics

| Component | Approach | Endpoint |
|-----------|----------|----------|
| Redpanda | Native Prometheus at `/public_metrics` | `:9644` |
| RabbitMQ | `rabbitmq_prometheus` plugin | `:15692` |
| Redis | `oliver006/redis_exporter` sidecar | `:9121` |
| PostgreSQL | `prometheus-community/postgres_exporter` sidecar | `:9187` |

Redpanda's `/public_metrics` is used instead of `/metrics` to avoid
high-cardinality per-partition label explosion.

### Production deployment

Grafana Alloy runs as a **sidecar container** in every ECS task definition.
Alloy receives OTLP on `localhost:4318` (intra-task) and remote-writes to
Grafana Cloud. The local `config.alloy` and production `config.prod.alloy`
differ only in three endpoint URLs — no dashboard or alert-rule changes needed
for the transition.

### PII constraints

No customer MSISDN, card PAN, customer name, merchant email, or OAuth token
may appear in any log, span attribute, or metric label. `db.statement`
attributes on spans touching `users`, `merchants`, and `kyb_documents` tables
are redacted in Alloy via `otelcol.processor.attributes` before export.

## Consequences

### Positive
- Single OTel SDK across all four runtimes; no vendor agent to update.
- Local dev environment is architecturally identical to production — same
  Alloy config, same dashboards.
- Grafana Cloud migration is non-breaking: three endpoint URL changes in one
  config file.
- OpenLIT + Langfuse together close both the infrastructure and product-level
  LLM observability gaps.
- Faraday auto-instrumentation gives end-to-end traces across Portal → Core
  with zero application code changes.

### Negative / Trade-offs
- More self-managed components in local dev (Alloy, Loki, Tempo, Prometheus,
  Grafana, Langfuse containers).
- Langfuse requires its own RDS-backed deployment in production; it cannot
  reuse the existing application database to avoid schema coupling.
- OpenLIT covers Anthropic calls in the Python scoring service only. Elixir
  Core LLM calls require manual span instrumentation using `gen_ai.*`
  semantic conventions.
