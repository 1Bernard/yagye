# Payment Lifecycle

**Last updated:** 2026-08-30

This document traces a mobile money payment from the merchant's API call through
to settlement. It is the most important flow in the system — everything else
(invoices, payouts, disputes) is structurally similar but simpler.

---

## End-to-end sequence

```
Merchant client
    │
    │  POST /v1/payments
    │  Authorization: Bearer sk_live_...
    │  Idempotency-Key: abc-123
    │
    ▼
[:v1 pipeline plugs — in order]
    │
    ├─ AuditLog         → writes api_requests row (trace_id, method, path, merchant_id)
    ├─ RateLimit        → checks hammer counter for merchant_id; 429 if exceeded
    ├─ Authenticate     → resolves API key → merchant_id, mode; 401 if invalid/revoked
    ├─ VerifyMode       → asserts request mode matches key mode; 422 if mismatch
    └─ Idempotency      → upserts idempotency_keys row; returns cached response if replay
    │
    ▼
PaymentController.create/2
    │
    ├─ CastAndValidate  → OpenApiSpex validates body against CreatePaymentRequest schema
    │
    ▼
Payments.create_payment(merchant_id, attrs)
    │
    ├─ resolve_customer     → Customers.find_or_create(merchant_id, customer_reference)
    │                          INSERT ... ON CONFLICT DO NOTHING + fetch
    │
    ├─ check_velocity       → VelocityChecker.check(merchant_id, customer_id, attrs)
    │                          Compares amount vs max_single_txn, daily + monthly sums
    │                          Returns :ok or {:error, :single_txn_limit_exceeded | ...}
    │
    ├─ insert_payment       → Ecto.Multi transaction:
    │   │                      INSERT INTO payments (state: "created", ...)
    │   │                      INSERT INTO payment_events (type: "payment.created", ...)
    │   │                      INSERT INTO outbox_messages (event_type: "payment.created", ...)
    │   └─ all three rows commit atomically or roll back together
    │
    └─ Oban.insert(PaymentDispatchWorker, %{payment_id: ...})
           → schedules dispatch job (does not execute it inline)
    │
    ▼
201 Created → merchant receives payment with state: "created"
    │
    │  [async — Oban executes PaymentDispatchWorker]
    ▼
PaymentDispatchWorker.perform/1
    │
    ├─ Routing.evaluate(merchant_id, mode, payment_attrs)
    │   ├─ Fetch merchant-scope rules (if any) by priority
    │   ├─ Evaluate conditions against payment attributes
    │   ├─ If no merchant match: fetch platform-scope rules by priority
    │   └─ Returns {:ok, provider_id} or {:error, :no_matching_route}
    │
    ├─ Providers.resolve_credential(merchant_id, provider_id, mode)
    │   → Fetches encrypted credential from provider_credentials, decrypts via Vault
    │
    ├─ UPDATE payments SET state = "dispatching"
    │   INSERT INTO payment_attempts (state: "pending", ...)
    │   INSERT INTO outbox_messages (event_type: "payment.dispatched", ...)
    │   [single transaction]
    │
    ├─ ProviderAdapter.charge(provider_code, credential, payment_attrs)
    │   → HTTP call to real provider (or gateway_simulator in dev/CI)
    │   → Returns {:ok, %{reference: "...", status: "pending"}}
    │         or {:error, %{code: "insufficient_funds"}}
    │         or {:error, :timeout}
    │
    ├─ [on provider success / pending]
    │   UPDATE payment_attempts SET state = "submitted", provider_reference = "..."
    │   UPDATE payments SET state = "pending_provider"
    │
    └─ [on provider hard failure]
        UPDATE payment_attempts SET state = "failed", failure_code = "..."
        → retry logic: schedule new attempt with backoff if retries remain
           else: UPDATE payments SET state = "failed"
    │
    │  [async — provider sends webhook to /provider-webhooks/:provider_code]
    ▼
ProviderWebhookController.receive/2
    │
    ├─ Verify HMAC signature (provider-specific)
    ├─ Parse provider payload → normalise to internal event shape
    │
    ├─ [on payment success]
    │   Ecto.Multi:
    │   ├─ UPDATE payments SET state = "succeeded", provider_reference = "..."
    │   ├─ UPDATE payment_attempts SET state = "succeeded"
    │   ├─ Ledger.record_payment_success(payment)
    │   │   ├─ INSERT INTO ledger_entries (type: "payment")
    │   │   ├─ INSERT INTO ledger_postings × 4:
    │   │   │   DR  customer_float_account    (amount)
    │   │   │   CR  merchant_float_account    (amount - fee)
    │   │   │   CR  yagye_fee_account         (fee)
    │   │   │   DR  yagye_fee_account         (0 net, tax split if applicable)
    │   │   └─ UPDATE ledger_balances (running balance cache)
    │   ├─ INSERT INTO outbox_messages (event_type: "payment.succeeded", ...)
    │   └─ Webhooks.enqueue_delivery(merchant_id, "payment.succeeded", payload)
    │       └─ INSERT INTO outbox_messages (type: "webhook.delivery", ...)
    │
    └─ 200 OK to provider (prevents provider retrying)
    │
    │  [async — outbox relay dispatches projection and webhook jobs]
    ▼
OutboxRelayWorker.perform/1
    │
    ├─ Fetches batch of unprocessed outbox_messages
    ├─ Dispatches one Oban job per message:
    │   ├─ ProjectionWorker → updates portal read-model (payments table in portal_db)
    │   ├─ MerchantBalanceProjection → updates proj_merchant_balances
    │   └─ WebhookDeliveryWorker → HTTP POST to merchant's webhook endpoint
    │
    └─ Marks outbox_messages.processed_at = now()
```

---

## State machine

```
created
   │
   └─ PaymentDispatchWorker picks up
          │
          ▼
      dispatching
          │
          ├─ provider returns success/pending
          ▼
      pending_provider
          │
          ├─ webhook: success
          ▼                  ▼
      succeeded           failed
```

Valid transitions are enforced by `Payment.state_changeset/3` and the
`@allowed_transitions` map. Any code attempting an illegal transition gets
an Ecto changeset error, not a silent write.

---

## Retry and failure handling

### Provider timeouts

If the provider HTTP call times out, the attempt is marked `timeout`. Oban
retries the worker with exponential backoff (default: 3 attempts, 5s / 30s / 5m
delays). Each retry creates a new `payment_attempts` row — the attempt history
is preserved.

### Hard provider failures

Failures with a `final: true` error code (e.g. `invalid_account`, `blocked`)
do not retry. The payment transitions directly to `failed`.

### Idempotency on retry

Each `PaymentDispatchWorker` execution checks whether a submitted attempt
already exists for this payment before calling the provider. If found, it skips
the provider call and processes the existing attempt's result. This prevents
double-charging on Oban retries.

---

## Ledger entries produced by a successful payment

Every successful payment produces exactly 4 postings in a single
`ledger_entries` row. The double-entry invariant (sum of all postings = 0) is
enforced by `Ledger.assert_balanced!/1` before inserting.

| Account | Direction | Amount | Why |
|---|---|---|---|
| `customer_float` | DR | full amount | Customer's balance decreases |
| `merchant_float` | CR | amount − fee | Merchant receives net amount |
| `yagye_revenue` | CR | fee | Yagye earns the spread |
| `yagye_revenue` | DR | 0 (tax split handled separately) | Tax liability |

The fee is computed by `Pricing.compute_fee(provider_id, amount, currency)` and
stored on the payment row at dispatch time. It never changes after the fact.

---

## Settlement flow (downstream of payment success)

Settlements run periodically (daily by default). The settlement batch job:

1. Selects all `succeeded` payments not yet included in a settlement.
2. Groups by `(merchant_id, provider_id, currency, mode)`.
3. Creates a `settlement_batches` row and `settlements` rows (one per provider
   statement expected).
4. Transitions payments to `in_settlement`.
5. When the provider sends their settlement report (via webhook or file),
   `Settlement.receive_provider_report/2` records the reported amounts and
   runs `run_matching/1` — computes variance and transitions to `matched` or
   `mismatched`.

Mismatched settlements surface in the ops portal for manual review. See
`docs/runbooks/common-incidents.md` → settlement mismatch.

---

## What is not covered here

- **Invoice payments** — an invoice can be paid by a customer via a payment link
  (P16). The payment flow is identical; an additional step links the payment to
  the invoice and transitions it to `paid`.
- **Payout flow** — merchant withdraws from their float. Uses
  `PayoutSagaWorker`; similar structure but the provider call is a credit-push
  to the merchant's bank/mobile account.
- **Dispute / refund flow** — disputes are raised against a succeeded payment;
  refunds are provider credit-pushes that reverse the original ledger postings.
