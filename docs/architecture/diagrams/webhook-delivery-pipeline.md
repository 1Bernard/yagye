# Merchant Webhook Delivery Pipeline

Last updated: 2026-10-18

```
MERCHANT WEBHOOK DELIVERY PIPELINE
=====================================
Last updated: 2026-10-18

PURPOSE: Push payment events to merchant-configured HTTP endpoints
         reliably, with retry, backoff, and dead-letter handling.

──────────────────────────────────────────────────────────────────────────────

FULL PIPELINE OVERVIEW:

CORE                          RABBITMQ                     PORTAL
─────                         ────────                     ──────

payment.succeeded
  (outbox relay)
       │
       ▼
Oban: WebhookFanoutWorker
  Loads all active endpoints
  subscribed to this event type
  for this merchant
       │
       │  For each endpoint:
       │  amqp_channel.basic_publish(
       │    exchange: "webhooks.delivery",
       │    routing_key: "mch_018e...",   ← per-merchant
       │    payload: delivery_payload
       │  )
       │
       ▼
┌──────────────────────────────────────────────────────┐
│  RabbitMQ Exchange: "webhooks.delivery"               │
│  Type: direct                                        │
│                                                      │
│  Binding:  routing_key = "mch_018e..."               │
│    → Queue: "webhooks.mch_018e..."                   │
│                                                      │
│  Dead-letter exchange: "webhooks.dlx"                │
│  (receives messages rejected after max retries)      │
└──────────────────────────┬───────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────┐
│  Per-merchant RabbitMQ Queue                          │
│  "webhooks.mch_018e..."                              │
│                                                      │
│  prefetch_count: 20  (flow control)                  │
└──────────────────────────┬───────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────┐
│  Portal: Broadway consumer                            │
│  concurrency: 10 processor slots                     │
│                                                      │
│  For each message:                                   │
│    1. Upsert portal_webhook_deliveries               │
│       ON CONFLICT (endpoint_id, event_id, attempt)   │
│       → record attempt start                        │
│                                                      │
│    2. HTTP POST to merchant endpoint                 │
│       Req, 10s timeout                              │
│       body: { event JSON }                          │
│       headers: X-Yagye-Signature: HMAC-SHA256        │
│                                                      │
│    3. Record result (status_code, response_body)     │
│       → update portal_webhook_deliveries             │
│                                                      │
│    4. ALWAYS ACK the RabbitMQ message               │
│       (do NOT reject-and-requeue)                   │
│       → removes from queue regardless of outcome    │
│                                                      │
│    5. If delivery FAILED:                            │
│       → Oban: WebhookDeliveryRetryWorker            │
│               scheduled_at = NOW() + backoff        │
└──────────────────────────┬───────────────────────────┘
                           │
                    ┌──────▼────────────────────────────┐
                    │  Merchant Endpoint                 │
                    │  (customer's HTTP server)          │
                    │                                   │
                    │  Expected: 2xx response            │
                    │  Timeout: 10 seconds               │
                    └──────┬────────────────────────────┘
                           │
               ┌───────────▼─────────────────────────┐
               │  Response received?                   │
               └──┬───────────────────────────────┬───┘
                  │ 2xx                            │ Non-2xx or timeout
         ┌────────▼────────┐            ┌──────────▼───────────────────────┐
         │  Record success  │            │  Record failure                   │
         │  done.           │            │  consecutive_failures++           │
         └──────────────────┘            │  Enqueue retry (Oban backoff)    │
                                         └──────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

RETRY BACKOFF SCHEDULE (Oban exponential):

  Attempt 1:  immediate
  Attempt 2:  5 minutes
  Attempt 3:  30 minutes
  Attempt 4:  2 hours
  Attempt 5:  8 hours
  Attempt 6:  24 hours
  ...
  Attempt 10: 3 days
  → discarded to DLX after max_attempts

──────────────────────────────────────────────────────────────────────────────

WHY ALWAYS-ACK (NOT reject-and-requeue)?

  ✗ WRONG: Broadway on_failure: :reject_and_requeue
    RabbitMQ immediately requeues the message.
    Broadway receives it again within milliseconds.
    Result: tight retry loop that saturates the consumer,
            starves successful deliveries.

  ✓ CORRECT: Always ACK + Oban retry
    ACK removes the message from the queue.
    Oban schedules the retry at the correct backoff time.
    Result: retry timing is decoupled from the consumer loop.
            Successful deliveries are never starved.

──────────────────────────────────────────────────────────────────────────────

THREE DEDUPLICATION LAYERS:

  Source of duplicates:
    - RabbitMQ message redelivered after consumer crash before ACK
    - Oban retry worker re-enqueues a delivery
    - WebhookFanoutWorker runs twice (Oban retry)

  Layer 1: Core DB
    outbox_messages.event_id UNIQUE
    Each event relayed exactly once from the outbox.

  Layer 2: Portal DB
    portal_webhook_deliveries UPSERT
    ON CONFLICT (endpoint_id, event_id, attempt)
    Two attempts to record the same delivery are collapsed.

  Layer 3: Endpoint dedup
    portal_webhook_endpoints UPSERT on endpoint_id
    Duplicate endpoint fan-out suppressed.

──────────────────────────────────────────────────────────────────────────────

CONSECUTIVE FAILURES AND AUTO-DISABLE:

  portal_webhook_endpoints
    consecutive_failures  integer  default 0
    disabled_at           timestamptz NULL

  On each failed delivery:
    consecutive_failures++

  On each successful delivery:
    consecutive_failures = 0

  When consecutive_failures >= 50:
    disabled_at = NOW()
    merchant receives portal notification + email alert

  Re-enabling:
    Merchant must explicitly re-enable via portal (not automatic).
    consecutive_failures resets to 0 on re-enable.

──────────────────────────────────────────────────────────────────────────────

DEAD-LETTER EXCHANGE (DLX):

  After max_attempts Oban retries, the job is discarded to DLX.

  ┌─────────────────────────────────────────────┐
  │  DLX Queue: "webhooks.dlx"                  │
  │                                             │
  │  DLX consumer:                              │
  │    Records final failed delivery            │
  │    Marks endpoint disabled (if not already) │
  │    Sends ops alert                          │
  └─────────────────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

WEBHOOK SIGNATURE (merchant verification):

  Header: X-Yagye-Signature: sha256=<hex>

  Computed as:
    HMAC-SHA256(webhook_endpoint.signing_secret, raw_body)

  The merchant verifies this on their server:
    computed = HMAC-SHA256(their_secret, request.body)
    provided = request.headers["X-Yagye-Signature"].split("sha256=")[1]
    secure_compare(computed, provided) # must be constant-time

  If signature doesn't match: ignore the webhook.
  This prevents spoofed webhook delivery from other actors.

──────────────────────────────────────────────────────────────────────────────

SOFT DELETE FOR WEBHOOK ENDPOINTS (ADR-0026):

  portal_webhook_endpoints.deleted_at  timestamptz NULL

  Hard delete is not possible because portal_webhook_deliveries
  references the endpoint. A hard delete would orphan delivery records,
  breaking the audit trail.

  Soft delete allows:
    - Delivery records remain queryable (JOIN still works)
    - Active endpoint list excludes deleted endpoints (WHERE deleted_at IS NULL)
    - Full delivery history preserved for compliance queries
```
