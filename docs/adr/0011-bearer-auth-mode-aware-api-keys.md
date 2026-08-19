# ADR-0011: Bearer Token Auth with Mode-Aware API Keys

**Date:** 2026-08-18
**Status:** Accepted

---

## Context

A payment platform serves two distinct environments:

- **Simulation** — safe for development and integration testing; no real money moves
- **Live** — production; real money, real consequences

A naive single-key model has a critical failure mode: test code accidentally
hits the live API. This has caused real financial incidents at other payment
providers. The key design must make this mistake structurally impossible.

Additionally, publishable keys (used client-side, in browser JavaScript or
mobile apps) must never grant the same capabilities as secret keys (used
server-side, never exposed to end users).

Stripe's model — test/live key pairs, publishable/secret distinction — is the
dominant pattern in payments and carries an existing mental model for integrating
developers.

---

## Decision

API keys have four properties that together define their capabilities:

| Property | Values | Purpose |
|----------|--------|---------|
| `kind` | `secret` \| `publishable` | What operations the key can perform |
| `mode` | `simulation` \| `live` | Which environment the key targets |
| `scopes` | `["*"]` or `["resource:action", …]` | Fine-grained permission set |
| `secret_hash` | argon2 hash | The verifiable credential |

**Authentication flow** (`YagyeCoreWeb.Plugs.Authenticate`):

1. Read `Authorization: Bearer <token>` header (or `X-API-Key: <token>`)
2. Split token at the first `_` to extract `key_prefix` (lookup index)
3. Query `api_keys WHERE key_prefix = $1 AND revoked_at IS NULL`
4. Verify raw token against `secret_hash` using `Argon2.verify_pass/2`
5. On success: set `conn.assigns.merchant` and `conn.assigns.api_key`

**Mode enforcement** (`YagyeCoreWeb.Plugs.VerifyMode`):

Routes declare which modes they accept. The plug compares the key's `mode`
against the route's allowed modes and halts with 403 if they do not match.
This makes it impossible for a simulation key to reach a live endpoint.

**Key structure:**

```
key_<uuid7>                    ← raw token (shown once on creation)
     └── prefix: key_<first-8-chars>   ← stored, used for lookup
         secret_hash: argon2(raw_token) ← stored, never logged
```

The prefix enables O(1) lookup without scanning all active keys. The full raw
token is never stored — only the argon2 hash.

**Wildcard scope (`*`)** grants all permissions. Scoped keys (e.g.,
`["merchants:read"]`) are validated by the controller or a future Authorize
plug. The bootstrap admin key uses `["*"]` and `mode: "simulation"`.

**Key issuance** returns the raw token exactly once in the response body. It
is never returned again. Lost keys must be revoked and reissued.

---

## Consequences

**Positive**
- Mode separation is structural, not procedural — a simulation key cannot
  reach a live endpoint regardless of the caller's intent.
- Argon2 hashing is intentionally slow, rate-limiting brute-force attacks
  against the credential store even if the database is compromised.
- The prefix lookup avoids a full-table scan on every authenticated request.
- One-time raw token display follows industry practice (Stripe, Braintree)
  and prevents credential sprawl in logs and dashboards.

**Negative / Trade-offs**
- Argon2 verification adds latency (~100–300ms per request). This is
  acceptable for the security guarantee and is applied once per request
  before any business logic. A future optimisation could cache the resolved
  key in a short-lived ETS entry keyed by token hash.
- Publishable keys require a separate trust boundary at the client layer.
  A publishable key in browser JavaScript can be read by anyone who inspects
  the page — scopes must be designed accordingly (read-only, no mutations).
- The `["*"]` wildcard scope exists for bootstrap and internal tooling. It
  must not be issued to external merchant keys. This is a convention, not a
  system constraint, and must be enforced in the issuance UI.
