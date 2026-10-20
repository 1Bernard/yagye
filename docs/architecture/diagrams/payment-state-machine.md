# Payment Dispatch State Machine

Last updated: 2026-10-18

```
PAYMENT DISPATCH STATE MACHINE
================================
Last updated: 2026-10-18

PURPOSE: Show the full lifecycle of a payment and its associated
         payment_attempt, including all failure modes and the
         resolution_pending reconciliation path.

──────────────────────────────────────────────────────────────────────────────

PAYMENT STATES (payments table):

  pending          — payment record created, not yet dispatched
  processing       — dispatch in progress
  succeeded        — provider confirmed charge succeeded
  failed           — provider confirmed charge failed (definitively)
  refunded         — full refund issued
  partially_refunded — partial refund issued
  voided           — voided before capture (card only)
  disputed         — chargeback initiated by customer
  abandoned        — max retries exhausted, no resolution

──────────────────────────────────────────────────────────────────────────────

PAYMENT_ATTEMPT STATES (payment_attempts table):

  created            — attempt record written, HTTP not yet sent
  dispatched         — HTTP request sent to provider, awaiting response
  succeeded          — provider confirmed charge succeeded
  failed             — provider confirmed charge failed (definitely)
  resolution_pending — HTTP request timed out, callback not yet received
  timed_out          — reconciliation confirmed no charge was applied
  abandoned          — maximum retries exhausted

──────────────────────────────────────────────────────────────────────────────

FULL STATE DIAGRAM:

┌────────────────────────────────────────────────────────────────────────────┐
│  POST /v1/payments                                                         │
│  Idempotency check passes                                                  │
│  Velocity check passes                                                     │
│  Pricing resolved                                                          │
│  Routing resolved → provider selected                                      │
└───────────────────────────────────────────────┬────────────────────────────┘
                                                │
                               ┌────────────────▼────────────────┐
                               │  payment.state = 'pending'        │
                               │  payment_attempt.state = 'created'│
                               └────────────────┬────────────────┘
                                                │
                                  PaymentDispatchWorker (Oban)
                                                │
                               ┌────────────────▼────────────────┐
                               │  HTTP POST to provider           │
                               │  payment_attempt = 'dispatched'  │
                               └───────────┬─────────────────────┘
                                           │
              ┌────────────────────────────┼──────────────────────────────┐
              │                            │                              │
              ▼                            ▼                              ▼
   Provider says: FAIL          Provider says: SUCCESS        HTTP TIMEOUT
   (insufficient_funds,         (sync response OR            (no response)
    invalid MSISDN, etc.)       async callback)
              │                            │                              │
              ▼                            ▼                              ▼
  error_class:                  payment_attempt                payment_attempt
  'definite_failure'             .state = 'succeeded'          .state = 'resolution_pending'
  'invalid'                                                     payment.state = 'processing'
              │                            │                              │
              ▼                            ▼                              │
  payment_attempt                payment                                 │
  .state = 'failed'              .state = 'succeeded'                    │
  payment                                 │                              │
  .state = 'failed'              LEDGER ENTRIES written:                 │
                                 DR suspense → CR float                  │
  (If retryable_error:           DR float → CR merchant_payable          │
   schedule retry with           DR float → CR fee_payable               │
   exponential backoff.                    │                              │
   On max retries:)              Outbox: payment.succeeded event          │
              │                                                           │
              │                                                           │
              │                                         ┌─────────────────▼─────────────┐
              │                                         │  ReconciliationWorker (daily) │
              │                                         │                               │
              │                                         │  Query provider with          │
              │                                         │  payment_attempt.idempotency_ │
              │                                         │  token                        │
              │                                         └──┬───────────────────┬────────┘
              │                                            │                   │
              │                                  ┌─────────▼──────┐  ┌────────▼──────────────┐
              │                                  │ Provider says:  │  │ Provider says:         │
              │                                  │ SUCCEEDED       │  │ FAILED / NOT FOUND    │
              │                                  └─────────┬──────┘  └────────┬──────────────┘
              │                                            │                   │
              │                                  payment_attempt         payment_attempt
              │                                  .state = 'succeeded'    .state = 'timed_out'
              │                                  (late booking)          payment.state = 'failed'
              │                                  Write ledger entries     (if within window)
              │                                  (late, effective_at=    OR
              │                                   original timestamp)    .state = 'abandoned'
              │                                                           (if max window elapsed)
              │
              │ RETRYABLE ERROR PATH:
              │
    ┌─────────▼──────────────────────────────┐
    │  If error_class = 'retryable_error':    │
    │                                        │
    │  Oban: schedule retry                  │
    │  delay = exponential backoff           │
    │  max_attempts = 5 (configurable)       │
    │                                        │
    │  New payment_attempt row created       │
    │  for each retry attempt                │
    └─────────┬────────────────────────────  ┘
              │ On max retries exceeded:
              ▼
    payment.state = 'abandoned'
    ops alert triggered

──────────────────────────────────────────────────────────────────────────────

ERROR CLASSES (payment_attempts.error_class):

  definite_failure   — Provider confirmed the charge failed.
                       Do not retry. Mark payment failed immediately.
                       Examples: insufficient_funds, invalid_msisdn,
                                account_frozen, duplicate_transaction

  retryable_error    — Transient provider error. Retry with backoff.
                       Examples: provider 503, rate limit, connection reset

  indeterminate      — HTTP request timed out. No callback received.
                       Do NOT retry immediately (charge may have been applied).
                       Enter resolution_pending. Wait for reconciliation.

  invalid            — Our request was malformed. Return 422 to merchant.
                       Do not retry. Examples: unsupported currency, amount=0

──────────────────────────────────────────────────────────────────────────────

THE IDEMPOTENCY_TOKEN (to provider — not to be confused with merchant's key):

  payment_attempts.idempotency_token

  Generated by Core when dispatching.
  Sent to provider in the idempotency header.

  Purpose:
    If our dispatch HTTP call times out, the token allows us to later ask
    the provider: "Did the charge with token <tok> succeed?"

    This is the reconciliation mechanism for resolution_pending states.

  Our key (from merchant):  prevents duplicate payments from merchant
  Our token (to provider):  enables post-timeout status reconciliation

──────────────────────────────────────────────────────────────────────────────

ROUTING AUDIT (payment_attempts.routing_configuration_id):

  Every payment_attempt records which routing_configuration was active.

  Immutable: changing routing rules after dispatch does not affect
  historical records.

  Use: post-hoc analysis of "which payments were affected by the
  routing rule change on date X" without time-traveling through
  configuration history.
```
