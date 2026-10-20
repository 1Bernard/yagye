# Idempotency State Machine

Last updated: 2026-10-18

```
IDEMPOTENCY STATE MACHINE
==========================
Last updated: 2026-10-18

PURPOSE: Prevent duplicate charges when merchants retry API calls
         after network failures, timeouts, or process crashes.

SCOPE: Every mutating /v1 endpoint. Required for POST /v1/payments,
       POST /v1/refunds, POST /v1/disputes/respond.

KEY PRINCIPLE: The claim is inserted BEFORE execution begins.
               The response is cached AFTER execution completes.

──────────────────────────────────────────────────────────────────────────────

STATE DIAGRAM:

                                        ┌──────────────────────────────┐
                                        │  Client: POST /v1/payments   │
                                        │  Idempotency-Key: "order-42" │
                                        └──────────────────┬───────────┘
                                                           │
                              ┌────────────────────────────▼─────────────────┐
                              │  INSERT INTO idempotency_keys                 │
                              │    (merchant_id, key, state='in_progress',    │
                              │     request_fingerprint = SHA-256(body),      │
                              │     lease_expires_at = NOW() + 30s)           │
                              │  ON CONFLICT (merchant_id, key) DO NOTHING    │
                              └──────────────────┬───────────────────────────┘
                                                 │
                              ┌──────────────────▼───────────────────────────┐
                              │  Repo.get_by(IdempotencyKey, ...)             │
                              │  (required: Uniq.UUID never detects conflict   │
                              │   from the insert result alone)               │
                              └────┬─────────────────────────────────────┬───┘
                                   │                                     │
                        ┌──────────▼──────────┐             ┌───────────▼──────────────┐
                        │  key NOT FOUND       │             │  key FOUND               │
                        │  (our insert won)    │             │  (conflict)              │
                        └──────────┬──────────┘             └─────────────┬────────────┘
                                   │                                       │
                                   │                         ┌─────────────▼────────────┐
                                   │                         │  Check request_fingerprint │
                                   │                         │  SHA-256(body) matches?   │
                                   │                         └──┬──────────────────┬─────┘
                                   │                            │ NO               │ YES
                                   │                     ┌──────▼──────┐  ┌────────▼──────────┐
                                   │                     │ 400 Bad Req │  │  Check state       │
                                   │                     │ "key reused │  └─────────┬──────────┘
                                   │                     │  with diff  │            │
                                   │                     │  params"    │   ┌────────▼──────────────────┐
                                   │                     └─────────────┘   │  state = 'in_progress'    │
                                   │                                       │  AND lease NOT expired?   │
                                   │                                       └────┬──────────────────┬───┘
                                   │                                            │ YES              │ NO
                                   │                                    ┌───────▼──────┐  ┌───────▼──────────┐
                                   │                                    │  409 Conflict │  │  Re-claim lease  │
                                   │                                    │  "in progress"│  │  (process crashed│
                                   │                                    │  retry later  │  │   mid-execution) │
                                   │                                    └───────────────┘  └───────┬──────────┘
                                   │                                                               │
                                   │                                        ┌──────────────────────▼──────┐
                                   │                                        │  state = 'completed'         │
                                   │                                        │  → Replay stored response    │
                                   │                                        │    (response_status + body)  │
                                   │                                        │    No re-execution. Done.    │
                                   │                                        └─────────────────────────────┘
                                   │
                                   │                                        ┌──────────────────────────────┐
                                   │                                        │  state = 'failed'            │
                                   │                                        │  → 422 "previous attempt     │
                                   │                                        │    failed. Use a new key."   │
                                   │                                        └──────────────────────────────┘
                                   │
                        ┌──────────▼────────────────────────┐
                        │  EXECUTE THE OPERATION             │
                        │  (payment create, charge, etc.)    │
                        └──────────┬────────────────────────┘
                                   │
                    ┌──────────────▼─────────────────┐
                    │  SUCCESS                        │
                    │  UPDATE idempotency_keys        │
                    │    state = 'completed'          │
                    │    response_status = 201        │
                    │    response_body = {...}        │
                    │  (same transaction as payment)  │
                    └──────────┬──────────────────────┘
                               │
                    ┌──────────▼─────────────────────┐
                    │  Return 201 Created             │
                    │  to client                      │
                    └─────────────────────────────────┘


                    ┌──────────────────────────────────┐
                    │  FAILURE (business / validation)  │
                    │  UPDATE idempotency_keys          │
                    │    state = 'failed'               │
                    │    response_status = 422          │
                    │    response_body = {error: ...}   │
                    └──────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

STATE TABLE:

  State        | Meaning                    | Retry behaviour
  ─────────────┼────────────────────────────┼──────────────────────────────
  in_progress  | Execution is running        | Wait. Retry after lease expires.
  completed    | Execution succeeded         | Replay stored response. No re-run.
  failed       | Execution failed (biz rule) | Client must use a NEW key.

──────────────────────────────────────────────────────────────────────────────

LEASE EXPIRY AND CRASH RECOVERY:

  Scenario: Process receives request, inserts 'in_progress', then crashes.
  Without lease: key stays 'in_progress' forever. No retry possible.
  With lease:    After lease_expires_at (30s), the key can be re-claimed.
                 A subsequent retry inserts a new 'in_progress' row and
                 re-executes the operation.

  The lease is a safety net, not a timeout. It only activates on crash.
  Normal execution completes and updates state long before lease expires.

──────────────────────────────────────────────────────────────────────────────

PROVIDER-SIDE IDEMPOTENCY:

  When Core dispatches to a provider:
    Core generates an idempotency_token and sends it as the provider's
    idempotency header (e.g. Idempotency-Key for Stripe).

  This is OUR token sent TO the provider — separate from the MERCHANT'S
  idempotency key sent to us.

  Purpose: if our dispatch HTTP call times out, we can later query the
  provider with the idempotency_token to determine if the charge was applied.
  This is the mechanism that resolves 'resolution_pending' payment attempts.

  Our key (from merchant) → prevents duplicate payments
  Our token (to provider) → enables post-timeout reconciliation

──────────────────────────────────────────────────────────────────────────────

SCOPE: (merchant_id, key) is the unique composite key.
  Merchant A and Merchant B can both use key "order-42" without collision.
  Key scoping prevents cross-merchant key pollution.

RETENTION: Completed/failed keys are retained for 90 days, then swept.
  Redpanda's consumer offset retention is tuned to match.
```
