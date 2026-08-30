# Data Flow

**Last updated:** 2026-08-30

This document describes how data moves between the three applications and their
databases. It covers the write path (merchant API → core DB), the event path
(core → outbox → portal projections), and the read path (portal DB → dashboard).

---

## Overview

```
                  WRITE PATH
                  ──────────
Merchant API call
    │
    ▼
yagye_core (Phoenix)
    │  Ecto.Multi: entity row + outbox_messages row
    ▼
core_db (PostgreSQL)
    │  outbox_messages.processed_at IS NULL
    ▼
OutboxRelayWorker (Oban, polls every ~1s)
    │  batch fetch → dispatch Oban jobs
    ▼
    ├── ProjectionWorker ──────────────────────────► portal_db (PostgreSQL)
    │   (writes to portal read-model tables)
    │
    ├── WebhookDeliveryWorker ─────────────────────► Merchant webhook endpoint
    │   (HTTP POST to merchant's registered URL)
    │
    └── [P14] Redpanda producer ──────────────────► Redpanda topic
                                                        │
                                                        ▼
                                                  Karafka consumer
                                                  (yagye_portal process)
                                                        │
                                                        ▼
                                                  portal_db (read model)


                  READ PATH
                  ─────────
Browser (ops / merchant user)
    │
    ▼
yagye_portal (Rails, Phlex views)
    │  Pundit policy scope → query object → Pagy
    ▼
portal_db
    │  bounded by date window, merchant_code scope
    ▼
Rendered HTML (Turbo Frames for partial updates)
    │  Real-time balance/state updates via Solid Cable
    ▼
Browser

```

---

## The outbox pattern in detail

The outbox is the only channel through which core emits events to the outside
world. It eliminates the dual-write problem: if core updated an entity and then
tried to publish an event (two separate writes), a crash between the two would
leave the event unpublished. With the outbox, both the entity change and the
event row are written in the **same database transaction** — they either both
commit or both roll back.

```
BEGIN;
  UPDATE payments SET state = 'succeeded' WHERE id = $1;
  INSERT INTO payment_events (payment_id, type, ...) VALUES (...);
  INSERT INTO outbox_messages (event_type, payload, processed_at = NULL) VALUES (...);
COMMIT;
```

The relay picks up unprocessed messages and dispatches them asynchronously.
If the relay fails, the message stays in `outbox_messages` and is retried on
the next relay poll — no event is lost.

### Outbox → portal_db consistency guarantee

The portal's read model is **eventually consistent** with core's write model.
The typical lag is under 2 seconds (Oban poll interval + job execution). The
lag is visible in the portal via the `last_applied_at` freshness indicator on
the merchant balance card.

Authoritative financial data (e.g. "what is the exact balance?") must always be
read from core's write model, not from the portal projection. The portal
projection is for display and dashboards only.

---

## Portal read-model tables

The portal maintains its own denormalised copy of the entities it needs to
display. It does not read from core_db.

| Portal table | Populated by | Source event(s) |
|---|---|---|
| `payments` | `PaymentProjectionWorker` | `payment.*` |
| `portal_merchant_applications` | `MerchantProjectionWorker` | `merchant.*` |
| `portal_webhook_deliveries` | `WebhookDeliveryProjectionWorker` | `webhook.delivery.*` |
| `proj_merchant_balances` | `MerchantBalanceProjection` | `payment.succeeded`, `payout.completed` |
| `proj_daily_merchant_metrics` | `DailyMetricsWorker` (hourly recompute) | Reads from `payments` directly |

### Projection idempotency

Every projection worker uses one of two idempotency strategies (ADR-0015):

**Version fencing** — used for entity state projections (e.g. payment state):
```sql
INSERT INTO payments (public_id, state, ...)
VALUES ($1, $2, ...)
ON CONFLICT (public_id) DO UPDATE SET
  state = EXCLUDED.state, ...
WHERE payments.aggregate_version < EXCLUDED.aggregate_version;
```
A late-arriving event (lower version) does not overwrite a newer state.

**Event ID dedup** — used for running counters (e.g. balance increments):
```sql
INSERT INTO proj_dedup_log (event_id) VALUES ($1)
ON CONFLICT DO NOTHING;
-- Only increment if the INSERT succeeded (affected_rows = 1)
UPDATE proj_merchant_balances SET available = available + $amount
WHERE merchant_id = $merchant_id AND affected_rows = 1;
```
A counter increment is not idempotent — replaying it without dedup would
double-count. The dedup log prevents this.

---

## Internal API (portal → core)

The portal writes to core only via the `/internal` HTTP API, not via direct
database access. This preserves the single write model and allows core to
enforce business rules (validation, state machine transitions) regardless of
the caller.

```
yagye_portal
    │
    │  POST /internal/applications/:id/approve
    │  X-Service-Token: <shared_secret>
    │
    ▼
yagye_core
    │
    ├─ AuthenticateInternal plug validates X-Service-Token
    ├─ ApplicationsController.approve/2
    └─ Compliance.approve_application/1 → writes to core_db, publishes outbox event
```

The shared secret is a long random string stored in environment variables on
both sides. In production, network rules restrict `/internal` to requests
originating from the portal's IP range only — the secret is a defence-in-depth
measure, not the primary control.

---

## Provider webhook data flow

Providers (MTN MoMo, Stripe, etc.) send asynchronous result notifications to
core's `/provider-webhooks/:provider_code` endpoint. Core is the only entry
point for provider data — the portal never receives provider webhooks directly.

```
Provider (MTN MoMo)
    │
    │  POST /provider-webhooks/mtn_momo
    │  X-MTN-Signature: <hmac>
    │
    ▼
ProviderWebhookController.receive/2
    │
    ├─ Verify HMAC (provider-specific verification per ProviderAdapter)
    ├─ Normalise payload to internal event format
    ├─ Payments.handle_provider_callback(provider_code, event)
    │   └─ Updates payment state + ledger in one transaction + outbox event
    └─ 200 OK to provider (important — provider will retry on non-2xx)
```

**Critical invariant:** Always return 200 to the provider after verifying the
HMAC and persisting the event, even if downstream processing fails. Downstream
failures are retried by Oban. If core returns a 5xx, the provider retries the
webhook — potentially causing duplicate processing if the original write
succeeded but the response was lost.

---

## Mode data flow

The `mode` column on every record enforces environment isolation at the data
layer. The same flow applies in all three modes; only the provider target
changes:

| Mode | Provider target | Ledger entries | Settlement |
|---|---|---|---|
| `simulation` | gateway_simulator | Yes (in-memory) | No |
| `sandbox` | Provider sandbox APIs | Yes | No |
| `live` | Provider production APIs | Yes | Yes |

The `VerifyMode` plug in the `:v1` pipeline ensures the API key's mode matches
the request. Cross-mode data access (e.g. reading live payments with a sandbox
key) is rejected at the API layer before any DB query executes.

---

## Trace propagation

Every inbound request to core generates a `trace_id` (W3C traceparent format
or falls back to `X-Request-ID`). This ID is:

1. Stored in `api_requests.trace_id` for the audit log.
2. Propagated in the `Logger` metadata for all log lines in that request scope.
3. Forwarded in outgoing provider HTTP calls as `X-Request-ID` so provider
   logs can be correlated back to the original request.
4. Included in outbox_messages so downstream workers log the originating
   trace context.

To reconstruct the full data flow for any transaction, filter logs by
`trace_id`. This works across core, the outbox relay, projection workers, and
webhook delivery workers because they all inherit the trace context from the
originating request.
