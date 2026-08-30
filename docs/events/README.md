# Event Catalog

This directory documents all domain events published via the transactional outbox
(ADR-0014, ADR-0015). Events are serialised as JSON in `outbox_messages.payload`
and consumed by portal read-model projection workers via Karafka/Redpanda.

## Naming convention

`<aggregate>.<past_tense_verb>` — e.g. `payment.succeeded`, `merchant.approved`.

All events carry a common envelope:

```json
{
  "event_id":        "01a051a0-...",
  "event_type":      "payment.succeeded",
  "aggregate_id":    "pay_01a051a0-...",
  "aggregate_type":  "payment",
  "aggregate_version": 3,
  "occurred_at":     "2026-08-30T12:00:00.000Z",
  "payload":         { ... }
}
```

## Event registry

### Payments

| Event | Published when | Key payload fields |
|---|---|---|
| `payment.created` | Payment inserted | `public_id`, `merchant_id`, `amount`, `currency`, `mode` |
| `payment.dispatched` | Dispatch worker picks up job | `payment_id`, `provider_code`, `attempt_id` |
| `payment.succeeded` | Provider confirms success | `payment_id`, `provider_reference`, `fee_amount` |
| `payment.failed` | All retries exhausted | `payment_id`, `failure_code`, `failure_message` |
| `payment.pending_auth` | Awaiting 3DS / OTP | `payment_id`, `redirect_url` |

### Disputes & Refunds

| Event | Published when | Key payload fields |
|---|---|---|
| `dispute.opened` | Merchant opens dispute | `dispute_id`, `payment_id`, `reason` |
| `dispute.resolved` | Dispute closed | `dispute_id`, `outcome` |
| `refund.created` | Refund initiated | `refund_id`, `payment_id`, `amount` |
| `refund.succeeded` | Provider confirms refund | `refund_id`, `provider_reference` |

### Merchants

| Event | Published when | Key payload fields |
|---|---|---|
| `merchant.created` | Merchant onboards | `merchant_id`, `merchant_code`, `country` |
| `merchant.approved` | KYB approved by ops | `merchant_id`, `approved_at` |
| `merchant.suspended` | Ops suspends merchant | `merchant_id`, `reason` |

### Invoices

| Event | Published when | Key payload fields |
|---|---|---|
| `invoice.created` | Invoice created in draft | `invoice_id`, `merchant_id`, `total_amount` |
| `invoice.issued` | Invoice moved to open | `invoice_id`, `issued_at` |
| `invoice.paid` | Payment applied to invoice | `invoice_id`, `paid_at`, `amount_paid` |
| `invoice.voided` | Invoice voided | `invoice_id`, `voided_at` |

### Settlement

| Event | Published when | Key payload fields |
|---|---|---|
| `settlement.expected` | Batch closes, settlement created | `settlement_id`, `expected_gross`, `expected_net` |
| `settlement.reported` | Provider sends settlement report | `settlement_id`, `reported_net`, `variance` |
| `settlement.matched` | Variance = 0 | `settlement_id` |
| `settlement.mismatched` | Variance ≠ 0 | `settlement_id`, `variance` |

### Payouts

| Event | Published when | Key payload fields |
|---|---|---|
| `payout.created` | Payout job inserted | `payout_id`, `merchant_id`, `amount` |
| `payout.submitted` | Submitted to provider | `payout_id`, `provider_reference` |
| `payout.completed` | Provider confirms credit | `payout_id`, `completed_at` |
| `payout.failed` | Provider rejects payout | `payout_id`, `failure_code` |

## Consumer map

| Event(s) | Portal consumer | Projection table |
|---|---|---|
| `payment.*` | `PaymentProjectionWorker` | `payments` (read model) |
| `payment.succeeded` / `payment.failed` | `MerchantBalanceProjection` | `proj_merchant_balances` |
| `payment.*` | `DailyMetricsWorker` | `proj_daily_merchant_metrics` |
| `merchant.*` | `MerchantProjectionWorker` | `portal_merchant_applications` |
| `dispute.*`, `refund.*` | _(P12 — not yet built)_ | — |
| `invoice.*` | _(portal invoice page — future)_ | — |

## Adding a new event

1. Define the event struct in `YagyeCore.<Domain>.Events.<EventName>`.
2. Publish via `Outbox.publish/2` inside the domain transaction.
3. Add a row to this catalog (event_type, payload fields, consumer).
4. Write or update the portal projection worker.
5. Add integration test covering outbox → worker → read-model.
