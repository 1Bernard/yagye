# Event Catalog

All domain events published through the outbox (ADR-0014). Events are written
to `outbox_messages` as JSONB `EventEnvelope` payloads and relayed to:

- **Portal consumers** via Redpanda / Karafka topics (read-model projection)
- **Merchant webhooks** via Oban workers (outbound HTTP delivery)

Each entry documents: the event name, the context that emits it, the trigger,
and the payload fields. All envelopes share the common wrapper:

```json
{
  "event_id": "uuid-v7",
  "event_name": "payment.succeeded",
  "aggregate_id": "pay_018e…",
  "aggregate_type": "Payment",
  "aggregate_version": 3,
  "merchant_id": "uuid",
  "occurred_at": "2026-08-30T12:00:00.000000Z",
  "data": { ... }
}
```

---

## Payments

### `payment.created`
**Context:** `YagyeCore.Payments`
**Trigger:** Successful insert of a new payment row.
**Data:**
```json
{
  "public_id": "pay_…",
  "state": "pending",
  "mode": "live",
  "method": "momo",
  "amount": 10000,
  "currency": "GHS",
  "description": "Order #1234",
  "merchant_code": "mch_…",
  "merchant_reference": "order-1234",
  "customer_reference": "cust_…",
  "customer_msisdn": "233241000001",
  "customer_email": "customer@example.com"
}
```

### `payment.dispatched`
**Context:** `YagyeCore.Payments`
**Trigger:** Payment attempt submitted to a provider.
**Data:** Adds `provider_code`, `attempt_id`.

### `payment.succeeded`
**Context:** `YagyeCore.Payments`
**Trigger:** Provider callback confirms success.
**Data:**
```json
{
  "public_id": "pay_…",
  "state": "succeeded",
  "mode": "live",
  "method": "momo",
  "merchant_code": "mch_…",
  "merchant_reference": "order-1234",
  "description": "Order #1234",
  "provider_code": "mtn_momo_gh",
  "provider": "mtn_momo",
  "amount": 10000,
  "currency": "GHS",
  "net_amount": 9720,
  "checkout_session_id": "cks_…",
  "customer_msisdn": "233241000001",
  "customer_email": "customer@example.com",
  "paid_at": "2026-09-22T14:00:00.000000Z"
}
```
`net_amount` = `amount − fee_amount` when a fee record exists; falls back to
`amount` if fees have not yet been recorded (deferred to P14/P15).
**Projections updated:** `proj_payment_summaries`, `proj_merchant_balances`,
`proj_daily_merchant_metrics`.
**Webhook:** Delivered to merchant endpoint as event type `payment.paid`, with
`status: "paid"` (translated from internal `state: "succeeded"`).

### `payment.failed`
**Context:** `YagyeCore.Payments`
**Trigger:** Provider callback reports failure or no response after retries.
**Data:** Adds `failure_code`, `failure_message`.
**Webhook:** Delivered to merchant endpoint if subscribed to `payment.failed`.

---

## Disputes

### `dispute.created`
**Context:** `YagyeCore.Disputes`
**Trigger:** Merchant or provider raises a dispute against a payment.
**Data:** `public_id`, `payment_id`, `reason`, `amount`, `state: "submitted"`.

### `dispute.resolved`
**Context:** `YagyeCore.Disputes`
**Trigger:** Dispute transitions to `won` or `lost`.
**Data:** Adds `resolution`, `resolved_at`.
**Webhook:** `dispute.won` or `dispute.lost`.

### `refund.created`
**Context:** `YagyeCore.Disputes`
**Trigger:** Merchant initiates a refund.
**Data:** `public_id`, `payment_id`, `amount`, `currency`, `state`.

### `refund.completed`
**Context:** `YagyeCore.Disputes`
**Trigger:** Provider confirms refund processed.
**Data:** Adds `provider_reference`, `completed_at`.

---

## Invoices

### `invoice.created`
**Context:** `YagyeCore.Invoices`
**Trigger:** Invoice inserted in `draft` state.
**Data:** `public_id`, `merchant_id`, `customer_id`, `total_amount`, `currency`,
`state: "draft"`, `line_items: [...]`.

### `invoice.issued`
**Context:** `YagyeCore.Invoices`
**Trigger:** Invoice transitions `draft → open`.
**Data:** Adds `issued_at`.
**Webhook:** `invoice.issued`.

### `invoice.paid`
**Context:** `YagyeCore.Invoices`
**Trigger:** Payment received and applied to invoice.
**Data:** Adds `paid_at`, `amount_paid`.
**Webhook:** `invoice.paid`.

### `invoice.voided`
**Context:** `YagyeCore.Invoices`
**Trigger:** Invoice transitions to `void`.
**Data:** Adds `voided_at`.

---

## Settlements

### `settlement.created`
**Context:** `YagyeCore.Settlement`
**Trigger:** Settlement record created for a batch period.
**Data:** `public_id`, `merchant_id`, `provider`, `currency`, `period_start`,
`period_end`, `expected_gross`, `expected_fees`, `expected_net`.

### `settlement.reported`
**Context:** `YagyeCore.Settlement`
**Trigger:** Provider reports actual settlement figures.
**Data:** Adds `reported_gross`, `reported_fees`, `reported_net`,
`provider_settlement_reference`, `value_date`.

### `settlement.matched`
**Context:** `YagyeCore.Settlement`
**Trigger:** Reported net matches expected net (`variance = 0`).

### `settlement.mismatched`
**Context:** `YagyeCore.Settlement`
**Trigger:** Reported net differs from expected net (`variance ≠ 0`).
**Data:** Adds `variance` (signed integer, minor units).

### `settlement.disbursed`
**Context:** `YagyeCore.Settlement`
**Trigger:** Funds transferred to merchant bank account.

---

## Merchants / Compliance

### `merchant.application_submitted`
**Context:** `YagyeCore.Compliance`
**Trigger:** Merchant submits KYB onboarding form.

### `merchant.approved`
**Context:** `YagyeCore.Compliance`
**Trigger:** Ops approves KYB application.
**Projections updated:** Portal merchant status.

### `merchant.rejected`
**Context:** `YagyeCore.Compliance`
**Trigger:** Ops rejects KYB application with reason.

---

## Payouts

### `payout.created`
**Context:** `YagyeCore.Payouts`
**Trigger:** Merchant requests a payout.
**Data:** `public_id`, `merchant_id`, `amount`, `currency`, `destination_type`.

### `payout.submitted`
**Context:** `YagyeCore.Payouts`
**Trigger:** Payout dispatched to bank/MoMo.

### `payout.completed`
**Context:** `YagyeCore.Payouts`
**Trigger:** Provider confirms payout landed.
**Data:** Adds `provider_reference`, `completed_at`.
**Webhook:** `payout.completed`.

### `payout.failed`
**Context:** `YagyeCore.Payouts`
**Trigger:** Provider reports payout failure.
**Data:** Adds `failure_code`.
**Webhook:** `payout.failed`.

---

## Routing

### `routing.resolved`
**Context:** `YagyeCore.Routing`
**Trigger:** A routing rule matched for a payment.
**Data:** `payment_id`, `rule_id`, `scope`, `provider_id`, `mode`.
*Internal only — not delivered as a merchant webhook.*

### `routing.failed`
**Context:** `YagyeCore.Routing`
**Trigger:** No routing rule matched; payment cannot be dispatched.
**Data:** `payment_id`, `mode`, `reason: "no_route"`.
*Internal only.*

---

## Webhook Endpoints

These events are emitted to the `yagye.webhooks.v1` Redpanda topic (via the
outbox). The Portal's `WebhookEventsConsumer` (Karafka) projects them into
`portal_webhook_endpoints` and `portal_webhook_deliveries`.

### `webhook.endpoint.registered`
**Context:** `YagyeCore.MerchantWebhooks`
**Trigger:** Merchant creates a webhook endpoint.
**Data:** `endpoint_id`, `merchant_code`, `url`, `mode`, `active`,
`subscribed_events`, `consecutive_failures`.

### `webhook.endpoint.updated`
**Context:** `YagyeCore.MerchantWebhooks`
**Trigger:** Merchant updates URL or subscribed events.
**Data:** Same fields as `webhook.endpoint.registered`.

### `webhook.endpoint.deregistered`
**Context:** `YagyeCore.MerchantWebhooks`
**Trigger:** Merchant deletes a webhook endpoint.
**Data:** `endpoint_id`, `merchant_code`.
**Portal:** `WebhookEventsConsumer` calls `soft_delete!` — the
`portal_webhook_endpoints` row is retained so delivery log JOINs keep
resolving the URL (`deleted_at` is set rather than the row being removed).

### `webhook.delivery.attempted`
**Context:** `YagyeCore.MerchantWebhooks.RabbitMQ.DeliveryPipeline`
**Trigger:** Every HTTP delivery attempt (success or failure) against a
merchant endpoint. Emitted via the outbox after the attempt completes.
**Data:**
```json
{
  "delivery_id": "uuid-v7",
  "endpoint_id": "whe_…",
  "merchant_code": "mch_…",
  "webhook_event_id": "uuid-v7",
  "webhook_event_type": "payment.paid",
  "attempt": 1,
  "state": "delivered",
  "response_status": 200,
  "response_body": "ok",
  "request_body": { "id": "evt_…", "event": "payment.paid", "data": {} },
  "request_headers": { "X-Yagye-Signature": "sha256=…" },
  "duration_ms": 45,
  "delivered_at": "2026-09-22T14:00:00.000000Z"
}
```
`state` is one of `delivered | failed | exhausted`.

---

## API Keys

### `api_key.used`
**Context:** `YagyeCore.Merchants.Workers.ApiKeyUsageWorker`
**Trigger:** Any authenticated API request. Fired asynchronously (Oban job)
so it does not add latency to the request path.
**Data:** `key_id`, `mode`, `kind`, `last_used_at`.
*Internal only — not delivered as a merchant webhook.*

---

## Conventions

- Event names use dot-separated `aggregate.past_tense` format.
- `aggregate_version` increments with each state change on the aggregate. Used
  for version-fence idempotency in projection workers (ADR-0015).
- `event_id` is UUIDv7 — time-ordered, globally unique. Projection workers use
  it for deduplication of non-idempotent operations (e.g. counter increments).
- All monetary amounts are integers in minor units (pesewas for GHS, cents for
  USD). Never floats. See ADR-0002.
- `occurred_at` is UTC, microsecond precision.
