# System Topology

Last updated: 2026-10-18

```
YAGYE SYSTEM TOPOLOGY
=====================
Last updated: 2026-10-18

┌─────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL WORLD                                  │
│                                                                             │
│  ┌────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │  Merchant API       │  │  Merchant / Ops       │  │  PSP Providers     │  │
│  │  Clients            │  │  Portal Users         │  │  (MTN MoMo,        │  │
│  │  (REST integration) │  │  (browser)            │  │   Stripe, etc.)    │  │
│  └─────────┬──────────┘  └──────────┬────────────┘  └────────┬───────────┘  │
└────────────│─────────────────────────│────────────────────────│──────────────┘
             │ HTTPS (Bearer token)    │ HTTPS (session)        │ HTTPS (webhook)
             ▼                         ▼                         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  yagye_core  (Elixir / Phoenix 1.7)                                        │
│                                                                            │
│  Pipeline :v1           Pipeline :internal    Pipeline :provider_webhooks  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────────┐   │
│  │ /v1/*            │  │ /internal/*      │  │ /provider-webhooks/    │   │
│  │ Bearer API key   │  │ X-Service-Token  │  │ :provider_code         │   │
│  │ OpenApiSpex      │  │ firewall-gated   │  │ HMAC-SHA256 verify     │   │
│  │ CastAndValidate  │  │                  │  │                        │   │
│  └──────┬───────────┘  └──────┬───────────┘  └───────────┬────────────┘   │
│         │                     │                           │                │
│  ┌──────▼────────────────────────────────────────────────▼──────────────┐ │
│  │                         YagyeCore (domain layer)                       │ │
│  │  Payments  Merchants  Ledger  Routing  Settlement  KYB  Webhooks       │ │
│  │  (Ecto contexts — DDD-lite, no Commanded)                              │ │
│  └──────────────────────────────────┬────────────────────────────────────┘ │
│                                     │                                      │
│  ┌──────────────────────────────────▼────────────────────────────────────┐ │
│  │  Oban (PostgreSQL-backed job queue)                                    │ │
│  │  Queues: default | outbox | dispatch | webhooks | reconciliation       │ │
│  └──────────────────────────────────┬────────────────────────────────────┘ │
└─────────────────────────────────────│──────────────────────────────────────┘
                                      │ SQL
                                      ▼
                           ┌────────────────────┐
                           │     core_db         │
                           │   (PostgreSQL)      │
                           │                    │
                           │  payments           │
                           │  merchants          │
                           │  ledger_entries     │
                           │  ledger_postings    │
                           │  outbox_messages    │
                           │  idempotency_keys   │
                           │  routing_rules      │
                           │  settlement_batches │
                           │  oban_jobs          │
                           └────────────────────┘

                                ── OUTBOX RELAY ──
                      outbox_messages → Oban → Portal projection jobs
                                      ↓
                      (at P14: Oban relay replaced by Redpanda topic)

                         ┌────────────────────────┐
                         │    Redpanda  (P14+)     │
                         │  (Kafka-compatible)     │
                         │  Topic: payment.events  │
                         │  Topic: merchant.events │
                         └────────────┬────────────┘
                                      │ Karafka consumer (P14+)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  yagye_portal  (Ruby 3.3 / Rails 8)                                         │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Phlex views + Turbo + Hotwire  |  Devise+TOTP  |  Pundit RBAC       │  │
│  │  ECharts dashboards  |  Vite + Tailwind  |  i18n EN+FR               │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Solid Queue (background jobs)  |  Solid Cable (PostgreSQL NOTIFY)          │
│                                                                             │
│  Karafka consumer (P14: Redpanda → portal_payments, portal_merchants, ...)  │
│                                                                             │
│  X-Service-Token calls → yagye_core /internal/*  (write operations only)   │
└─────────────────────────────────────────────────────────────────────────────┘
                      │ SQL
                      ▼
           ┌────────────────────┐
           │    portal_db        │
           │   (PostgreSQL)      │
           │                    │
           │  users              │  ← auth, RBAC, sessions
           │  portal_payments    │  ← read model projection
           │  portal_merchants   │  ← read model projection
           │  portal_api_keys    │  ← mirrors core api_keys
           │  portal_webhook_*   │  ← webhook config + delivery
           │  roles/permissions  │  ← dynamic RBAC tables
           └────────────────────┘

──────────────────── DEV + CI ONLY ─────────────────────────

           ┌──────────────────────────────┐
           │    gateway_simulator          │
           │  (Elixir / Phoenix)           │
           │  SQLite — stateless           │
           │                              │
           │  Speaks same HTTP protocol   │
           │  as real providers.          │
           │                              │
           │  MSISDN 024 100 0001 → ok    │
           │  MSISDN 024 100 0002 → fail  │
           │  MSISDN 024 100 0003 → timeout│
           │                              │
           │  NEVER deployed to prod.     │
           └──────────────────────────────┘

──────────────────── OBSERVABILITY ──────────────────────────

           structured JSON logs → Grafana Alloy
           OTLP spans          → Grafana Alloy → Tempo
           Prometheus metrics  → Grafana Alloy → Metrics backend
                                       │
                                  Grafana dashboards
```
