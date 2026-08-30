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
  "merchant_id": "uuid",
  "customer_id": "uuid",
  "amount": 10000,
  "currency": "GHS",
  "method": "momo",
  "network": "MTN",
  "mode": "live",
  "state": "pending"
}
```

### `payment.dispatched`
**Context:** `YagyeCore.Payments`
**Trigger:** Payment attempt submitted to a provider.
**Data:** Adds `provider_code`, `attempt_id`.

### `payment.succeeded`
**Context:** `YagyeCore.Payments`
**Trigger:** Provider callback confirms success.
**Data:** Adds `provider_reference`, `fee_amount`, `net_amount`.
**Projections updated:** `proj_payment_summaries`, `proj_merchant_balances`,
`proj_daily_merchant_metrics`.
**Webhook:** Delivered to merchant endpoint if subscribed to `payment.succeeded`.

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

## Conventions

- Event names use dot-separated `aggregate.past_tense` format.
- `aggregate_version` increments with each state change on the aggregate. Used
  for version-fence idempotency in projection workers (ADR-0015).
- `event_id` is UUIDv7 — time-ordered, globally unique. Projection workers use
  it for deduplication of non-idempotent operations (e.g. counter increments).
- All monetary amounts are integers in minor units (pesewas for GHS, cents for
  USD). Never floats. See ADR-0002.
- `occurred_at` is UTC, microsecond precision.
