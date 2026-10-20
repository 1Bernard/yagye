# Outbox to Projection Pipeline

Last updated: 2026-10-18

```
OUTBOX → PROJECTION PIPELINE
==============================
Last updated: 2026-10-18

THE DUAL-WRITE PROBLEM (what the outbox solves):
─────────────────────────────────────────────────

  ✗ NAIVE (broken):
     1. UPDATE payments SET state = 'succeeded'   ← commits OK
     2. publish to Redpanda                       ← process crashes
     Result: payment succeeded, but no event published.
             Portal never updates. Merchant never gets webhook.

  ✗ ALSO BROKEN (reversed order):
     1. publish to Redpanda                       ← commits OK
     2. UPDATE payments SET state = 'succeeded'   ← process crashes
     Result: event published for a payment that didn't commit.
             Portal projects a phantom payment.

  ✓ OUTBOX (correct):
     All in ONE transaction:
       UPDATE payments SET state = 'succeeded'
       INSERT ledger_entries + ledger_postings
       INSERT outbox_messages (event_id, type, payload)
     If ANY fails → entire transaction rolls back.
     Event exists ↔ state change committed. Guaranteed.

──────────────────────────────────────────────────────────────────────────────

FULL PIPELINE (current — pre-P14):

┌──────────────────────────────────────────────────────────────────────────┐
│  CORE DB (PostgreSQL)                                                     │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Single ACID Transaction                                          │   │
│  │                                                                  │   │
│  │  UPDATE payments SET state='succeeded'                           │   │
│  │  INSERT ledger_postings (debit suspense, credit float, ...)       │   │
│  │  INSERT outbox_messages                                           │   │
│  │    id:              bigserial (sequential scan key)               │   │
│  │    event_id:        "01JKL..." (ULID — consumer dedup key)        │   │
│  │    event_type:      "payment.succeeded"                           │   │
│  │    aggregate_id:    "pay_018e..."                                 │   │
│  │    aggregate_version: 5                                           │   │
│  │    partition_key:   "mch_018e..." (merchant_id for ordering)      │   │
│  │    destination:     "internal:projections"                        │   │
│  │    envelope:        { full event payload jsonb }                  │   │
│  │    published_at:    NULL                                          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
                      │
                      │ (published_at IS NULL)
                      │
           ┌──────────▼──────────────┐
           │  OutboxRelayWorker       │  Oban cron, runs every ~1s
           │  (queue: outbox)         │
           │                         │
           │  SELECT id, event_id,   │
           │    event_type, ...       │
           │  FROM outbox_messages   │
           │  WHERE published_at IS NULL
           │  ORDER BY id ASC        │  ← bigserial: efficient sequential scan
           │  LIMIT 100              │
           └──────────┬──────────────┘
                      │  for each row
                      ▼
           ┌──────────────────────────┐
           │  Enqueue Oban job        │
           │  PaymentProjectionWorker │  (or MerchantProjectionWorker, etc.)
           │  args: event_id,         │
           │        aggregate_version,│
           │        payload           │
           └──────────┬───────────────┘
                      │
                      │  Mark relayed:
                      │  UPDATE outbox_messages
                      │  SET published_at = NOW()
                      │  WHERE id = $row_id

──────────────────────────────────────────────────────────────────────────────

PROJECTION WORKER — IDEMPOTENCY:

           ┌─────────────────────────────────────────────────────────────┐
           │  PaymentProjectionWorker (Oban job)                          │
           │                                                             │
           │  1. Upsert portal_payments with VERSION FENCING:            │
           │                                                             │
           │     INSERT INTO portal_payments                             │
           │       (core_payment_id, status, aggregate_version, ...)     │
           │     VALUES ($core_id, $status, $version, ...)               │
           │     ON CONFLICT (core_payment_id) DO UPDATE                 │
           │       SET status            = EXCLUDED.status,              │
           │           aggregate_version = EXCLUDED.aggregate_version    │
           │       WHERE portal_payments.aggregate_version               │
           │             < EXCLUDED.aggregate_version;  ← fencing        │
           │                                                             │
           │     A redelivered event with lower version → no-op ✓       │
           │                                                             │
           │  2. For COUNTER updates (merchant balance):                 │
           │                                                             │
           │     INSERT INTO processed_events                            │
           │       (event_id, consumer)                                  │
           │     VALUES ($event_id, 'merchant_balance')                  │
           │     ON CONFLICT DO NOTHING;                                 │
           │                                                             │
           │     IF 1 row inserted:                                      │
           │       UPDATE portal_merchant_balances                       │
           │         SET balance = balance + $net_amount                 │
           │     ELSE:                                                   │
           │       skip (already processed) ✓                           │
           └──────────────────────────────────────┬──────────────────────┘
                                                  │
                                                  ▼
                                       ┌─────────────────────┐
                                       │    PORTAL DB         │
                                       │                     │
                                       │  portal_payments    │
                                       │  portal_merchants   │
                                       │  portal_merchant_   │
                                       │    balances         │
                                       │  processed_events   │
                                       └──────────┬──────────┘
                                                  │
                                          Solid Cable NOTIFY
                                                  │
                                                  ▼
                                        ┌────────────────┐
                                        │    BROWSER      │
                                        │  Turbo Stream   │
                                        │  live update    │
                                        │  (no reload)    │
                                        └────────────────┘

──────────────────────────────────────────────────────────────────────────────

AT P14: OUTBOX RELAY REPLACED BY REDPANDA

  Current (pre-P14):
    outbox_messages → OutboxRelayWorker (Oban) → PaymentProjectionWorker (Oban)

  At P14:
    outbox_messages → OutboxRelayWorker (Oban) → Redpanda topic "payment.events"
                                                          │
                                                    Karafka consumer
                                                          │
                                              PaymentProjectionConsumer
                                         (same idempotency logic, different driver)

  The projection worker logic does not change.
  The idempotency strategies (version fencing, processed_events) are broker-agnostic.
  The outbox schema does not change.
  Only the relay mechanism changes.

──────────────────────────────────────────────────────────────────────────────

GUARANTEES SUMMARY:

  "Effectively once" = at-least-once delivery + idempotent consumer

  Outbox guarantees:    event exists ↔ state change committed
                        (no phantom events, no lost events)

  Version fencing:      stale STATE events are no-ops
  processed_events:     duplicate COUNTER events are discarded

  Result:               portal projection always converges to correct state
                        typical lag: 1–3 seconds (outbox relay + job queue)
                        maximum lag: defined by Oban queue backpressure
```
