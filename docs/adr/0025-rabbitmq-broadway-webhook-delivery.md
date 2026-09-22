# ADR-0025: RabbitMQ + Broadway for Outbound Webhook Delivery

**Date:** 2026-09-22
**Status:** Accepted

---

## Context

Outbound webhook delivery has different characteristics from internal background
jobs (ADR-0012):

- **Fan-out at dispatch time.** A single payment event may need to be delivered
  to multiple merchant endpoints simultaneously. An Oban job per endpoint
  enqueued inside a database transaction scales poorly — inserting 50 jobs for
  50 endpoints in one transaction holds write locks and inflates `oban_jobs`.
- **High concurrency with bounded latency.** Webhook delivery is I/O-bound
  (HTTP POST, 5s timeout). Oban's PostgreSQL-backed queue is well-suited for
  CPU-bound work and moderate concurrency; for high-throughput HTTP fan-out it
  adds unnecessary lock contention.
- **Backpressure and flow control.** At high event volume the delivery pipeline
  must be able to slow consumption without dropping messages or exhausting the
  database connection pool.
- **Separation of concerns.** Retry policy should not live inside the message
  broker (`reject_and_requeue` in RabbitMQ creates tight loops with no backoff).
  The broker is responsible for durable queuing; retry scheduling is business
  logic that belongs in the application.

Oban (ADR-0012) remains correct for all internal domain jobs. A dedicated
message broker is warranted specifically for outbound webhook fan-out.

---

## Decision

**Outbound webhook delivery uses RabbitMQ as the transport and Broadway
(BroadwayRabbitMQ) as the consumer. Oban drives retry scheduling.**

### Dispatch path

`WebhookDispatchWorker` (Oban) is the bridge between the outbox and RabbitMQ.
It is enqueued by `OutboxRelayWorker` when a `payment.succeeded` (or any
subscribed) event is processed. The worker:

1. Fetches all active endpoints subscribed to the event type for the merchant.
2. For each endpoint, publishes a JSON delivery task to the
   `yagye.webhooks.delivery` RabbitMQ queue.

Publishing to RabbitMQ is decoupled from the database transaction — the Oban
job is the durability guarantee; the RabbitMQ message is the transport.

### Delivery path

A Broadway pipeline (`DeliveryPipeline`) consumes from the queue with
`prefetch_count: 20` and up to 10 concurrent processor slots:

1. Decrypts the HMAC signing secret (AES-256-GCM via Vault).
2. Wraps the domain payload in a stable event envelope (`id`, `event`,
   `created_at`, `livemode`, `data.object`).
3. Signs the envelope with HMAC-SHA256 (`X-Yagye-Signature: sha256=…`).
4. POSTs to the merchant URL (5s timeout, no redirects).
5. **Always acks the RabbitMQ message** — regardless of HTTP outcome.
6. Records the attempt in `merchant_webhook_deliveries`.
7. Emits `webhook.delivery.attempted` to the outbox → Redpanda → Portal.
8. On failure, schedules `WebhookDeliveryRetryWorker` (Oban) with exponential
   backoff.

### Retry policy

`WebhookDeliveryRetryWorker` is an Oban job (`queue: :webhooks, max_attempts: 1`):

| Attempt | Delay before next attempt |
|---------|--------------------------|
| 1 → 2  | 10 seconds               |
| 2 → 3  | 60 seconds               |
| 3 → 4  | 10 minutes               |
| 4 → 5  | 1 hour                   |
| 5      | No retry — exhausted     |

The retry worker fetches the endpoint's **current URL from the database** before
re-publishing to RabbitMQ. This means a URL update by the merchant takes effect
on the next retry without any queue manipulation.

### Deduplication strategy

The delivery pipeline is designed for at-least-once delivery. Three layers
prevent duplicate records; they do not prevent duplicate HTTP POSTs.

**Layer 1 — Core DB (`merchant_webhook_deliveries`)**

`record_delivery/1` upserts with `conflict_target: [:endpoint_id, :event_id, :attempt]`:

```elixir
Repo.insert(changeset,
  on_conflict: {:replace, [:state, :response_status, :response_body,
                            :duration_ms, :delivered_at, :updated_at]},
  conflict_target: [:endpoint_id, :event_id, :attempt]
)
```

If the same RabbitMQ message is processed twice (e.g. Broadway crashes after
the HTTP POST but before the ack, and RabbitMQ redelivers the unacked message
on reconnect), the second insert updates the existing record rather than
creating a duplicate row. The `delivery_id` field is not in the conflict
`on_conflict` list, so the first generated ID wins.

**Layer 2 — Portal DB (`portal_webhook_deliveries`)**

`WebhookEventsConsumer` upserts on `unique_by: :delivery_id`. Replaying a
`webhook.delivery.attempted` event (e.g. Karafka consumer restart) is safe
— it updates the record in place rather than inserting a duplicate.

**Layer 3 — Portal DB (`portal_webhook_endpoints`)**

`WebhookEventsConsumer` upserts endpoints on `unique_by: :endpoint_id`.
Out-of-order Redpanda replays do not create duplicate endpoint rows.

### At-least-once delivery — merchant obligation

The three dedup layers above protect Yagye's internal records. They do **not**
prevent a merchant's endpoint from receiving the same HTTP POST twice.

**Scenario:** Broadway processes a message, POSTs successfully to the merchant,
then crashes before acking RabbitMQ. On reconnect, RabbitMQ redelivers the
message. Broadway processes it again — another POST goes to the merchant with
a new `X-Yagye-Delivery` ID (a fresh UUIDv7 generated per attempt).

The merchant sees two deliveries with different `X-Yagye-Delivery` headers but
identical event payloads and the same event `id`.

**Merchant obligation:** Implement idempotency keyed on the event `id` field
(`data.object.id` for payments), not on `X-Yagye-Delivery`. The delivery
header is a per-attempt identifier for logging — it changes on each attempt
and cannot be used for deduplication.

### Why `on_failure: :reject` (not `:reject_and_requeue`)

`:reject_and_requeue` causes RabbitMQ to immediately re-deliver the message to
the same consumer — creating a tight retry loop at full concurrency with no
backoff. Combined with Broadway's prefetch buffer, in-flight messages survive
queue purges and continue cycling until the queue is deleted. Oban's
`WebhookDeliveryRetryWorker` is the correct place for retry scheduling: it has
backoff, a max-attempts ceiling, and reads a fresh URL.

---

## Consequences

### Positive
- Webhook fan-out does not compete for `oban_jobs` write locks during
  high-throughput events.
- Broadway's backpressure (min/max demand) prevents the pipeline from
  overwhelming downstream endpoints or saturating the connection pool.
- Retry policy is explicit, testable, and decoupled from the broker.
- A URL update by the merchant is automatically picked up on the next retry.
- The dead-letter exchange (`yagye.webhooks.dead`) captures permanently failed
  messages for ops inspection without data loss.

### Negative / Trade-offs
- RabbitMQ is a new infrastructure dependency. It must be in the HA checklist
  and the Compose / Kubernetes manifests.
- In-flight messages prefetched by Broadway survive a queue purge — to discard
  stuck messages, the queue must be **deleted** (not purged), which causes
  Broadway to reconnect and recreate it clean.
- The delivery pipeline is stateless (always acks); durability depends on
  `WebhookDeliveryRetryWorker` being enqueued before Broadway crashes. If the
  process crashes between the HTTP result and the Oban insert, the delivery
  is lost without a retry. This window is small (microseconds) and acceptable
  given that the delivery record in `merchant_webhook_deliveries` is written
  in the same code path.

### Relationship to other ADRs
- **ADR-0012**: Oban remains the job queue for all internal domain work. The
  `WebhookDispatchWorker` and `WebhookDeliveryRetryWorker` are Oban workers;
  RabbitMQ is the transport between them and the delivery pipeline.
- **ADR-0014**: The transactional outbox is still the source of truth for event
  emission. RabbitMQ carries delivery tasks, not domain events — domain events
  continue to flow through the outbox → Redpanda path.
