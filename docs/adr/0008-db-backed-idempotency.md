# ADR-0008: PostgreSQL-Backed Idempotency State Machine

**Date:** 2026-08-18
**Status:** Accepted

---

## Context

Payment APIs must be safe to retry. A client that times out on a `POST /payments`
request cannot know whether the charge was applied. Without idempotency, a retry
creates a duplicate charge. With it, the second request replays the first
response without re-executing the side effect.

Common implementation approaches considered:

| Approach | Durability | Atomicity | Auditability | Complexity |
|----------|-----------|-----------|--------------|-----------|
| Redis TTL key | No — lost on restart | Partial | None | Low |
| In-memory ETS | No | No | None | Very low |
| Header passthrough to provider | Provider-dependent | Provider-dependent | None | Low |
| PostgreSQL state machine | Yes | Yes (DB constraints) | Full | Medium |

Payment operations must be durable (survives application restarts), atomic (no
double-execution under concurrent retries), and auditable (what ran, when, and
what it returned). Only the PostgreSQL approach satisfies all three.

---

## Decision

Idempotency is implemented as a **PostgreSQL-backed state machine** with an
explicit `claim → in_progress → completed | failed` lifecycle.

**State machine:**

```
          ┌──────────────┐
          │  (no record) │
          └──────┬───────┘
                 │ claim/4 — new key
                 ▼
          ┌──────────────┐
          │  in_progress │ ◄─── concurrent retry → :in_progress error
          └──────┬───────┘
         ┌───────┴────────┐
         │                │
         ▼                ▼
   ┌──────────┐    ┌──────────┐
   │completed │    │  failed  │
   └──────────┘    └──────────┘
         │
         │ same key + same fingerprint
         ▼
    replay stored response
```

**Key design decisions:**

1. **Atomic claim via `ON CONFLICT DO NOTHING`**: the insert either creates the
   row (claim succeeds) or silently skips (conflict). Atomicity is guaranteed by
   the database unique constraint on `(merchant_id, key)`.

2. **Conflict detection via follow-up read**: Ecto's `autogenerate: true`
   pre-generates the struct UUID before the insert, so `{:ok, idem_key}` is
   returned even when the conflict fires and no row was written. The resolved
   pattern is: after `Repo.insert(on_conflict: :nothing)`, call
   `Repo.get(IdempotencyKey, idem_key.id)` — if `nil`, the insert was skipped
   (conflict); if present, the claim succeeded.

3. **Request fingerprint**: the SHA-256 hash of the raw request body is stored at
   claim time. A replay attempt with a different fingerprint (same key, different
   body) returns `:fingerprint_mismatch` rather than replaying — this protects
   against accidentally reusing a key for a different operation.

4. **Lease expiry**: an `in_progress` key holds a 30-second lease
   (`lease_expires_at`). After expiry, a new claim attempt returns
   `:lease_expired` rather than `:in_progress`, allowing recovery from crashed
   workers.

5. **Failed keys are terminal**: a `failed` key returns `:previous_attempt_failed`
   on any subsequent claim. The client must use a new idempotency key to retry.
   This is intentional — it prevents replaying a partial state.

**Raw body capture**: `YagyeCoreWeb.CachingBodyReader` wraps `Plug.Parsers`'s
body reader and stores the raw binary in `conn.private` before parsing. This
allows the idempotency plug to hash the exact bytes sent by the client.

---

## Consequences

**Positive**
- Fully durable — idempotency state survives application restarts.
- Distributed-safe — multiple nodes competing to claim the same key resolve
  correctly via the DB constraint.
- Auditable — every idempotency key, its state, request fingerprint, stored
  response, and timestamps are queryable.
- Replay is exact — the stored `response_body` and `response_status` are
  returned verbatim; the operation is never re-executed.

**Negative / Trade-offs**
- Every mutating request incurs at least one extra DB roundtrip (the claim).
  Completed requests incur two (claim + get to detect conflict). This is
  acceptable given that the operations themselves (payment processing, ledger
  writes) are far more expensive.
- The `Idempotency-Key` header is optional. Callers without it bypass the
  mechanism entirely — the API does not mandate idempotency keys (consistent
  with Stripe's approach).
- `failed` keys are not retryable with the same key. Clients must generate new
  keys for retries after failures. This must be clearly documented.
