# Payment Lifecycle Sequence

Last updated: 2026-10-18

```
PAYMENT LIFECYCLE SEQUENCE DIAGRAM
===================================
Last updated: 2026-10-18

Shows the full path of a successful MoMo payment from API call to ledger posting.

Actors:
  [MERCHANT]  — merchant's backend system
  [CORE]      — yagye_core Phoenix application
  [CORE_DB]   — core PostgreSQL database
  [SIMULATOR] — gateway_simulator (dev/CI) or real MTN MoMo (prod)
  [OBAN]      — Oban job queue (PostgreSQL-backed)
  [PORTAL_DB] — portal PostgreSQL database
  [BROWSER]   — merchant's portal browser tab

─────────────────────────────────────────────────────────────────────────────

PHASE 1: REQUEST INTAKE AND IDEMPOTENCY CLAIM
─────────────────────────────────────────────

[MERCHANT]        [CORE]                          [CORE_DB]
    │                │                                │
    │ POST /v1/payments                               │
    │ Idempotency-Key: order-42                       │
    │ Bearer: sk_live_...                             │
    │─────────────────►│                              │
    │                  │                              │
    │                  │ 1. VerifyMode plug           │
    │                  │    key.mode = 'live' ✓       │
    │                  │                              │
    │                  │ 2. OpenApiSpex validate      │
    │                  │    body schema OK ✓          │
    │                  │                              │
    │                  │ 3. INSERT idempotency_keys   │
    │                  │    (merchant_id, 'order-42') │
    │                  │    state = 'in_progress'     │
    │                  │    lease_expires_at = +30s   │
    │                  │    ON CONFLICT DO NOTHING    │
    │                  │─────────────────────────────►│
    │                  │                              │
    │                  │ 4. Fetch row (Uniq.UUID fix) │
    │                  │◄─────────────────────────────│
    │                  │    new row → proceed         │

PHASE 2: VELOCITY CHECK AND PAYMENT CREATION
─────────────────────────────────────────────

    │                  │ 5. Check velocity limits     │
    │                  │    merchant risk_tier=low ✓  │
    │                  │    customer tier_2 ✓         │
    │                  │                              │
    │                  │ 6. Resolve pricing           │
    │                  │    specificity match → 2.5%  │
    │                  │    fee_amount = 250 pesewas  │
    │                  │                              │
    │                  │ 7. Resolve routing rule      │
    │                  │    currency=GHS, method=momo │
    │                  │    network=mtn               │
    │                  │    → mtn_momo_gh provider    │
    │                  │                              │
    │                  │ 8. Ecto.Multi transaction:   │
    │                  │    INSERT payments           │
    │                  │    INSERT payment_attempts   │
    │                  │    (state=created, both)     │
    │                  │─────────────────────────────►│
    │                  │                              │

PHASE 3: PROVIDER DISPATCH
───────────────────────────

    │                  │                              │
    │                  │ 9. PaymentDispatchWorker     │
    │                  │    (Oban, queue: dispatch)   │
    │                  │                              │
    │                  │ 10. Generate idempotency_token │
    │                  │     (our token TO provider)  │
    │                  │                              │
[SIMULATOR / MTN MOMO]
    │                  │                              │
    │                  │ POST /charge                 │
    │                  │ X-Idempotency-Token: tok_abc │
    │                  │─────────────────────────────────────────────►│
    │                  │                                              │
    │                  │◄──────────────────────────────────────────── │
    │                  │ 200 OK, status: "pending"                    │
    │                  │ (MoMo is async — user gets USSD prompt)      │
    │                  │                              │
    │                  │ UPDATE payment_attempts      │
    │                  │   state = 'dispatched'       │
    │                  │─────────────────────────────►│

PHASE 4: PROVIDER CALLBACK
───────────────────────────

    │                  │                                              │
    │                  │◄─────────────────────────────────────────────│
    │                  │ POST /provider-webhooks/mtn_momo_gh          │
    │                  │ X-MoMo-Signature: <hmac>                     │
    │                  │ body: {transaction_ref, status: "SUCCESSFUL"} │
    │                  │                              │
    │                  │ 11. HMAC verify              │
    │                  │     secure_compare ✓         │
    │                  │     (constant-time)          │
    │                  │                              │
    │                  │ 12. Ecto.Multi:              │
    │                  │  UPDATE payments             │
    │                  │    state = 'succeeded'       │
    │                  │  INSERT ledger_entries (x2)  │
    │                  │  INSERT ledger_postings:     │
    │                  │    DR suspense    10000      │
    │                  │    CR float_acct  10000      │
    │                  │    DR float_acct  10000      │
    │                  │    CR merch_pay    9750      │
    │                  │    CR fee_pay       250      │
    │                  │  INSERT outbox_messages      │
    │                  │    event: payment.succeeded  │
    │                  │  UPDATE idempotency_keys     │
    │                  │    state = 'completed'       │
    │                  │─────────────────────────────►│
    │                  │                              │ ← single ACID transaction
    │                  │ 200 OK (always ack provider) │
    │                  │─────────────────────────────────────────────►│

PHASE 5: OUTBOX RELAY AND PORTAL PROJECTION
─────────────────────────────────────────────

[OBAN]            [CORE_DB]   [PORTAL_DB]   [BROWSER]
    │                 │            │              │
    │ OutboxRelayWorker (every ~1s)│              │
    │ SELECT WHERE published_at IS NULL           │
    │────────────────►│            │              │
    │◄───────────────  row: payment.succeeded     │
    │                 │            │              │
    │ UPDATE outbox_messages       │              │
    │   published_at = NOW()       │              │
    │────────────────►│            │              │
    │                 │            │              │
    │ Enqueue PaymentProjectionWorker             │
    │                 │            │              │
    │ PaymentProjectionWorker runs │              │
    │ UPSERT portal_payments       │              │
    │   ON CONFLICT (core_payment_id)             │
    │   WHERE aggregate_version <  │              │
    │──────────────────────────────►│             │
    │                 │            │              │
    │                 │ Solid Cable NOTIFY        │
    │                 │────────────────────────── ►│
    │                 │            │   Turbo Stream update
    │                 │            │   (payment status badge
    │                 │            │    updates live in portal)

PHASE 6: MERCHANT WEBHOOK DELIVERY
────────────────────────────────────

    │                 │            │
[OBAN]            [RABBITMQ]   [MERCHANT SERVER]
    │                 │              │
    │ WebhookFanoutWorker          │
    │   For each endpoint subscribed to payment.succeeded:
    │   Publish to exchange "webhooks.delivery"
    │────────────────►│             │
    │                 │             │
    │ Broadway consumer picks up   │
    │ HTTP POST to merchant endpoint │
    │──────────────────────────────►│
    │                 │             │ 200 OK
    │◄──────────────────────────────│
    │ Record delivery success       │
    │ in portal_webhook_deliveries  │

─────────────────────────────────────────────────────────────────────────────

DUPLICATE REQUEST PATH (idempotency replay):

[MERCHANT]        [CORE]
    │                │
    │ POST /v1/payments (SAME key: order-42)
    │─────────────────►│
    │                  │
    │                  │ INSERT ... ON CONFLICT DO NOTHING (0 rows affected)
    │                  │ Fetch row → state = 'completed'
    │                  │
    │                  │ Return stored response_body (HTTP 201)
    │◄─────────────────│ No re-execution. No duplicate charge.
```
