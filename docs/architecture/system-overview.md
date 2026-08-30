# System Overview

**Last updated:** 2026-08-30

This document describes the Yagye platform at the component level: what each
service is, what it owns, and how the pieces connect. Read this before any
other architecture document.

---

## What Yagye is

Yagye is a **Payment Service Provider (PSP)** built for the West African market.
In Model A (current), Yagye is the PSP — it holds float accounts, KYBs merchants,
and routes payments through its own provider network. In Model B (P13+), Yagye
additionally acts as an orchestration layer for large enterprise merchants who
want to route across their own provider contracts.

---

## Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                          External World                              │
│  Merchant API clients   Merchant portal users   PSP Providers        │
│  (REST integrations)    (browser, ops users)    (MTN MoMo, Stripe…)  │
└────────────┬───────────────────┬───────────────────────┬────────────┘
             │ HTTPS             │ HTTPS                 │ HTTPS
             ▼                   ▼                       ▼
┌─────────────────────┐ ┌──────────────────┐  ┌──────────────────────┐
│   yagye_core        │ │   yagye_portal   │  │  Provider webhooks   │
│   (Phoenix / Elixir)│ │   (Rails 8)      │  │  → /provider-webhooks│
│                     │ │                  │  │    /:provider_code   │
│  /v1  — merchant API│ │  Dashboard       │  └──────────────────────┘
│  /internal — portal │◄├──(X-Service-Key) │
│  /provider-webhooks │ │  Karafka consumer│
└────────┬────────────┘ └────────┬─────────┘
         │                       │
         │ SQL                   │ SQL
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│  core_db        │     │  portal_db      │
│  (PostgreSQL)   │     │  (PostgreSQL)   │
└────────┬────────┘     └─────────────────┘
         │ Oban / outbox relay
         ▼
┌─────────────────┐
│   Redpanda      │  (Kafka-compatible broker, P14)
│   (P14+)        │  Currently: Oban jobs carry events
└─────────────────┘

┌─────────────────────────────┐
│  gateway_simulator          │  (Elixir/Phoenix)
│  (dev + CI only)            │  Stands in for real PSP providers.
│  Never deployed to prod.    │  Controlled via X-Simulator-* headers.
└─────────────────────────────┘
```

---

## yagye_core

**Language / framework:** Elixir 1.17 + Phoenix 1.7 + Ecto 3  
**Database:** PostgreSQL (core_db)  
**Background jobs:** Oban (PostgreSQL-backed)  
**Observability:** OpenTelemetry + logger_json

### What it owns

- The authoritative write model for every financial entity: payments, merchants,
  customers, invoices, disputes, refunds, payouts, settlements, ledger entries.
- The double-entry ledger — the only place where money is moved.
- All routing logic (platform rules + merchant-scope overrides at P16).
- Provider dispatch and webhook ingestion.
- The transactional outbox — every domain state change publishes an event row
  in the same DB transaction that mutates the entity.

### API surfaces

| Surface | Pipeline | Auth | Purpose |
|---|---|---|---|
| `POST /v1/*` | `:v1` | Bearer API key | Merchant-facing write operations |
| `GET /v1/*` | `:v1` | Bearer API key | Merchant-facing read operations |
| `POST /internal/*` | `:internal` | X-Service-Token | Portal → core ops (KYB disposition, routing rule management) |
| `POST /provider-webhooks/:code` | `:provider_webhooks` | HMAC (per provider) | Inbound provider callbacks |
| `GET /api/openapi` | `:api` | None | OpenAPI spec |

### Key internal boundaries (Boundary library)

Module exports are declared in `YagyeCore` (`lib/yagye_core.ex`). The web layer
(`YagyeCoreWeb`) may only reference modules listed in that export. This prevents
the controller layer from bypassing context functions to touch schemas directly.

---

## yagye_portal

**Language / framework:** Ruby 3.3 + Rails 8 + Phlex (custom, no PhlexUI)  
**Database:** PostgreSQL (portal_db) — a separate database from core  
**Background jobs:** Solid Queue  
**Real-time:** Solid Cable (PostgreSQL LISTEN/NOTIFY)  
**Event consumption:** Karafka (consuming from Redpanda at P14; currently Oban relay + direct DB write)  
**CSS / JS:** Tailwind CSS + Vite + ECharts

### What it owns

- A read-model projection of core data: `Payment`, `PortalMerchantApplication`,
  `PortalWebhookEndpoint`, `PortalWebhookDelivery`.
- User identity, authentication (email+password+TOTP), and sessions.
- Dynamic DB-backed RBAC: 8 roles, 21 permissions, enforced by Pundit policies.
- The ops-facing UI for Yagye internal staff (compliance, analyst, manager roles).
- The merchant-facing dashboard (owner, finance, developer, support roles).

### What it does NOT own

- The write model. Portal never writes financial records to core_db.
- Provider credentials or routing configuration directly — it calls
  `/internal/routing-rules` on core.
- Ledger entries, ledger balances — it reads projections (`proj_merchant_balances`).

### Portal → core communication

The portal calls core's `/internal` endpoints via `X-Service-Token`. This is
the only allowed direction for writes. Portal never writes to core_db directly.

---

## gateway_simulator

**Language / framework:** Elixir + Phoenix  
**Database:** SQLite (in-process, no persistence needed)  
**Deployment:** Development and CI only — never in production

### What it is

The anti-corruption layer (ADR-0013) that stands in for real PSP providers
during development and CI. It speaks the same HTTP protocol as real providers
(MTN MoMo, Stripe, Flutterwave, Paystack) so core's provider adapters are
tested against real HTTP semantics without sandbox credentials.

### Outcome control

Outcomes are controlled via fixed MSISDN prefixes and `X-Simulator-Outcome`
headers:

```
MSISDN 024 100 0001 → success
MSISDN 024 100 0002 → insufficient_funds
MSISDN 024 100 0003 → timeout
```

The simulator persists nothing between requests. It is stateless by design.

---

## External dependencies

| Dependency | Purpose | Phase introduced |
|---|---|---|
| PostgreSQL | Core write model, portal read model, Oban, idempotency, outbox | P1 |
| Redpanda | Event streaming broker (Kafka-compatible) | P14 |
| Redis | Distributed rate limiting, optional PubSub | P17 |
| AWS S3 + KMS | KYB document storage | P21 |
| MTN MoMo API | Mobile money provider (sandbox → production) | P1 |
| Stripe | Card provider (sandbox → production) | P13 |
| Flutterwave | Alternative provider (sandbox) | P13 |
| Paystack | Alternative provider (sandbox) | P13 |
| Floci | Local AWS emulator for dev/CI (S3, KMS) | P21 |
| Twilio / SMS | SMS notifications for OTP, payment receipts | P18 |

---

## Database separation

core_db and portal_db are separate PostgreSQL databases (and in production,
separate instances). This is deliberate:

- **Isolation:** A slow portal reporting query cannot lock core write transactions.
- **Security:** Portal credentials cannot touch the ledger or payment tables directly.
- **Scaling:** The two databases have different load profiles (core: write-heavy;
  portal: read-heavy analytics) and can be scaled independently.
- **Read-model freedom:** Portal schema is denormalised for reads and does not
  need to match core's normalised write model.

The two databases are kept consistent by the outbox → projection pipeline
(ADR-0015), not by replication. Projections are eventually consistent.

---

## Mode isolation

Every domain record in both databases carries a `mode` column:
`simulation | sandbox | live`.

- `simulation` — fully in-process, no real provider calls. Used for development
  and merchant testing. All providers route to the gateway_simulator.
- `sandbox` — real provider credentials, but sandbox/test accounts. Safe for
  integration testing.
- `live` — real money, real provider accounts.

The `:v1` pipeline's `VerifyMode` plug enforces that a request's API key mode
matches the resource mode. Cross-mode reads are impossible at the API layer.
The DB also stores mode on every row, enabling auditors to query
"show me all live payments" without any ambiguity.

---

## Security model overview

| Layer | Mechanism |
|---|---|
| Merchant API authentication | Bearer token (API key), mode-aware (ADR-0011) |
| Internal (portal → core) | X-Service-Token shared secret, firewall-gated |
| Provider webhook auth | HMAC-SHA256 per provider, verified in controller |
| Portal session | Devise (email+password+TOTP), session token in PostgreSQL |
| Portal authorisation | Pundit policies + DB-backed RBAC (ADR-0017) |
| Segregation of duties | DB CHECK constraints + changeset enforcement (SoD model doc) |
| No hard deletes | ON DELETE RESTRICT on all domain FKs (ADR-0020) |
| Idempotency | DB-backed idempotency state machine (ADR-0008) |
