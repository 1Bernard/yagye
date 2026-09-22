# API Conventions

**Last updated:** 2026-09-22

All merchant-facing endpoints under `/v1` follow these conventions. Internal
(`/internal`) and webhook (`/provider-webhooks`) endpoints share most of them
but have different auth and some different response shapes.

---

## Authentication

Every `/v1` request requires a Bearer token:

```
Authorization: Bearer sk_live_01a051a0-...
```

Keys are mode-aware: a `sk_live_` key only works against live-mode resources;
a `sk_sandbox_` key only works against sandbox-mode resources. The prefix is
also how the `VerifyMode` plug determines the request's intended mode.

Keys are never logged in full. The audit log records only `key_prefix` (first 8
characters). API keys are never hard-deleted — revoked keys remain in the DB
with `revoked_at` set (ADR-0009).

---

## Idempotency

All mutating requests (`POST`, `PATCH`) must include:

```
Idempotency-Key: <client-generated UUID or string, max 255 chars>
```

The key is scoped to the merchant — two merchants can use the same string
without collision. Replaying an identical request within the key's TTL (24h)
returns the original response without re-executing side effects. The response
includes `X-Idempotent-Replayed: true` when serving a cached result.

Keys are stored in `idempotency_keys` with a `SELECT ... FOR UPDATE` lock
during the first request — concurrent duplicate requests are serialised, not
both executed.

---

## Public IDs

All entity IDs exposed in API responses are `public_id` values — prefixed
UUIDv7 strings (ADR-0007):

```
pay_01a051a0-56af-74a4-8242-f87ef8e43348
mch_01a051a0-56af-74a4-8242-f87ef8e43348
inv_01a051a0-56af-74a4-8242-f87ef8e43348
```

The internal UUID `id` is never exposed. URL path parameters always carry the
`public_id`. Context functions resolve `public_id` → internal `id` via
`Repo.get_by(Entity, public_id: id)`.

---

## Request format

JSON body, `Content-Type: application/json`. Request schemas are validated by
OpenApiSpex (`CastAndValidate` plug) before the controller action runs. Invalid
bodies receive `422 Unprocessable Entity` with a structured error response (see
below) before any business logic executes.

---

## Response envelopes

### Single resource

```json
{
  "id": "pay_01a051a0-...",
  "object": "payment",
  "mode": "live",
  "state": "succeeded",
  ...
}
```

The `object` field names the entity type. It is always present and matches the
`id` prefix (e.g. `pay_` → `"object": "payment"`).

### List resource

```json
{
  "object": "list",
  "data": [ { "id": "pay_...", "object": "payment", ... }, ... ],
  "has_more": true
}
```

Lists never include a `total_count`. See ADR-0019.

---

## Pagination

All list endpoints use cursor-based pagination (ADR-0019):

| Parameter | Type | Description |
|---|---|---|
| `starting_after` | string | Return records older than this public_id |
| `ending_before` | string | Return records newer than this public_id |
| `limit` | integer | Records per page (default: 25, max: 100) |

**Forward traversal** (standard — fetch next page):
```
GET /v1/payments?limit=25
→ { data: [pay_Z, ..., pay_A], has_more: true }

GET /v1/payments?limit=25&starting_after=pay_A
→ { data: [pay_Y, ..., pay_B], has_more: false }
```

**Backward traversal** (fetch previous page):
```
GET /v1/payments?limit=25&ending_before=pay_A
→ { data: [pay_Z, ..., pay_B], has_more: true }
```

Only one of `starting_after` or `ending_before` may be present in a request.

---

## Error envelope

All errors use the same shape (ADR-0010):

```json
{
  "error": {
    "type": "invalid_request_error",
    "code": "payment_not_found",
    "message": "No payment with id pay_01a051a0-... exists for this merchant.",
    "param": null
  }
}
```

### Error types

| Type | HTTP status | When |
|---|---|---|
| `authentication_error` | 401 | Missing / invalid / revoked API key |
| `invalid_request_error` | 422 | Validation failure, bad param, wrong state transition |
| `not_found_error` | 404 | Resource does not exist or belongs to another merchant |
| `rate_limit_error` | 429 | Too many requests |
| `idempotency_error` | 409 | Idempotency key reused with different request body |
| `api_error` | 500 | Unexpected server error |

### Validation errors

Validation errors include `param` and may include a nested `errors` array:

```json
{
  "error": {
    "type": "invalid_request_error",
    "code": "validation_failed",
    "message": "Request body is invalid.",
    "param": "amount",
    "errors": [
      { "field": "amount", "message": "must be greater than 0" },
      { "field": "currency", "message": "is not included in the list" }
    ]
  }
}
```

---

## HTTP status codes

| Status | Meaning |
|---|---|
| 200 OK | Read or state-change succeeded |
| 201 Created | Resource created |
| 204 No Content | Not used (always return the resource) |
| 400 Bad Request | Malformed JSON |
| 401 Unauthorized | Auth failure |
| 404 Not Found | Resource does not exist |
| 409 Conflict | Idempotency key conflict |
| 422 Unprocessable Entity | Validation failure or invalid state transition |
| 429 Too Many Requests | Rate limit exceeded |
| 500 Internal Server Error | Unexpected error |

`DELETE` on a credential (API key) returns `200` with the revoked resource —
not `204`. This makes revocation auditable: the response body confirms what was
revoked and when. See ADR-0009.

---

## Versioning

The current API version is `v1`. The version is in the URL path (`/v1/...`),
not in a header. When a breaking change is required, a new `/v2/` scope is
added; `/v1/` remains active until all merchants have migrated.

Non-breaking additions (new optional fields, new optional query params, new
endpoint) are made to `/v1/` without incrementing the version.

`api_version` on the `Merchant` record tracks which version of the API
contract the merchant's integration is written against. This allows core to
adjust serialisation for older clients if needed.

---

## Rate limits

Default limits per API key (merchant + mode):

| Window | Limit |
|---|---|
| Per second | 20 requests |
| Per minute | 500 requests |
| Per hour | 5,000 requests |

Limits are enforced by the `Hammer` library with ETS backend (single-node) or
Redis backend (multi-node, P17). The response on limit breach:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 42
X-RateLimit-Limit: 20
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1722340800
```

---

## OpenAPI spec

The machine-readable spec is available at:

```
GET /api/openapi          → JSON spec
GET /swaggerui            → Interactive Swagger UI
```

The spec is generated at runtime from `YagyeCoreWeb.ApiSpec` and the
`open_api_operation/1` callbacks on each controller. Every new endpoint must
define its operation in the corresponding spec module under
`lib/yagye_core_web/api_specs/`.

The spec is also exported as a static JSON file to `contracts/openapi/yagye-core.json`
as part of the schema export process.

---

## Outbound Webhooks

Yagye delivers domain events to merchant-registered HTTPS endpoints. This
section documents the wire format, signature scheme, and the reliability
contract merchants must build against.

### Event envelope

Every POST body is a JSON event envelope:

```json
{
  "id": "evt_01j9qx…",
  "object": "event",
  "event": "payment.paid",
  "created_at": "2026-09-22T14:00:00.000000Z",
  "livemode": true,
  "data": {
    "object": {
      "id": "pay_01j9…",
      "object": "payment",
      "status": "paid",
      "amount": 10000,
      "net_amount": 9720,
      "currency": "GHS",
      "method": "momo",
      "provider": "mtn_momo",
      "merchant_reference": "order-1234",
      "customer_msisdn": "233241000001",
      "paid_at": "2026-09-22T14:00:00.000000Z"
    }
  }
}
```

**Internal → merchant event name translation:**

Domain events use past-tense internal names. The outbound webhook translates
them to merchant-facing names:

| Internal event | Merchant webhook event |
|---|---|
| `payment.succeeded` | `payment.paid` |
| `payment.failed` | `payment.failed` |
| `payout.completed` | `payout.completed` |
| `invoice.paid` | `invoice.paid` |

Correspondingly, the internal `state: "succeeded"` field is exposed as
`status: "paid"` in the `data.object`. Merchants see only the merchant-facing
names — the internal state names are never sent in webhook payloads.

### Request headers

| Header | Description |
|---|---|
| `Content-Type` | `application/json` |
| `User-Agent` | `Yagye-Webhook/1.0` |
| `X-Yagye-Signature` | HMAC-SHA256 signature (see below) |
| `X-Yagye-Delivery` | UUIDv7 per attempt — changes on every retry |
| `X-Yagye-Event` | Event name, e.g. `payment.paid` |
| `X-Yagye-Timestamp` | Unix timestamp of delivery attempt (seconds) |

### Signature verification

Every webhook POST is signed with the endpoint's signing secret using
HMAC-SHA256. The signature covers the raw request body bytes.

```
X-Yagye-Signature: sha256=<hex-encoded-hmac>
```

**Verification (pseudocode):**

```python
import hmac, hashlib

def verify_webhook(body_bytes, header, signing_secret):
    expected = "sha256=" + hmac.new(
        signing_secret.encode(),
        body_bytes,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, header)
```

```ruby
# Ruby
digest = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, request.body.read)
expected = "sha256=#{digest}"
ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Yagye-Signature"])
```

```javascript
// Node.js
const crypto = require('crypto');
const sig = crypto.createHmac('sha256', signingSecret)
                  .update(rawBody)
                  .digest('hex');
const expected = `sha256=${sig}`;
const valid = crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(header));
```

**Important rules:**
- Always use a **timing-safe comparison** (`hmac.compare_digest`, `timingSafeEqual`,
  `secure_compare`). String equality (`==`) is vulnerable to timing attacks.
- Compute the HMAC over the **raw body bytes**, not a parsed/re-serialised object.
  Whitespace differences in re-serialisation will break the signature.
- The signing secret is revealed **once only** when the endpoint is created. Store
  it immediately in an environment variable or secrets manager — it cannot be
  retrieved again.
- Optionally validate `X-Yagye-Timestamp` is within ±5 minutes to prevent replay
  attacks.

### At-least-once delivery

Yagye guarantees **at-least-once** delivery, not exactly-once. In rare failure
scenarios (process crash after a successful HTTP POST but before the RabbitMQ
ack), the same event may be delivered more than once. Duplicate deliveries will
have different `X-Yagye-Delivery` headers but identical event `id` values.

**Merchant obligation:** implement idempotency keyed on the event `id` field
(or the `data.object.id` of the resource). Do not key on `X-Yagye-Delivery` —
it is a per-attempt logging identifier, not a stable idempotency key.

```python
# Example: idempotent handler
def handle_webhook(event):
    if already_processed(event["id"]):
        return  # idempotent — skip duplicate
    process(event["data"]["object"])
    mark_processed(event["id"])
```

### Response expectations

Yagye considers any `2xx` response a successful delivery. Any other status
(including `3xx` redirects, which are not followed) is treated as a failure
and scheduled for retry per the exponential backoff policy (ADR-0025).

Respond as quickly as possible — the delivery times out at **5 seconds**. If
processing the event takes longer, respond `200` immediately and process
asynchronously.

### Endpoint suspension

After **50 consecutive delivery failures**, the endpoint is automatically
suspended (`active = false`, `disabled_at` set). Suspended endpoints receive
no further deliveries until explicitly re-enabled via the Portal developer
console or the API. The Portal shows a `consecutive_failures` badge on the
endpoint row when failures accumulate.

---

## Internal API (`/internal`)

The `/internal` scope is for portal → core communication only. It is not part
of the public merchant API.

- Auth: `X-Service-Token: <shared_secret>` (handled by `AuthenticateInternal` plug)
- Not rate-limited (internal traffic)
- Not idempotency-keyed (portal generates unique actions)
- Not versioned (same-codebase deployment)
- Never exposed beyond the VPC / private network in production

Endpoints on `/internal` do not need OpenAPI spec entries (they are not
merchant-facing and are not included in the published spec).
