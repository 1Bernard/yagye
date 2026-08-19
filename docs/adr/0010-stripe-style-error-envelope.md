# ADR-0010: Stripe-Style JSON Error Envelope

**Date:** 2026-08-18
**Status:** Accepted

---

## Context

Every API error response needs a consistent shape that clients can handle
programmatically. Without an explicit convention, different controllers return
different shapes depending on what generated the error:

- Phoenix's default validation errors: `%{errors: %{detail: "…"}}`
- Ecto changeset errors: a nested map of field → messages
- Authentication failures: ad-hoc shapes per controller

This inconsistency forces every client to write separate error-handling logic for
each endpoint. It also makes SDK generation brittle and support harder — a support
engineer reading a log cannot tell from the shape alone whether an error is a
client mistake or a server fault.

Stripe's error envelope is a well-known, widely-adopted pattern with an existing
mental model for developers in the payments space. Adopting it reduces the
learning curve for merchants integrating with Yagye.

---

## Decision

**All error responses use the Stripe error envelope:**

```json
{
  "error": {
    "type": "invalid_request_error",
    "code": "not_found",
    "message": "The requested resource does not exist."
  }
}
```

**Field semantics:**

| Field | Values | Meaning |
|-------|--------|---------|
| `type` | `invalid_request_error` | Client fault — bad input, wrong state, auth failure |
| `type` | `api_error` | Server fault — unexpected error, third-party failure |
| `code` | `not_found` | HTTP 404 — resource does not exist or is not accessible |
| `code` | `validation_error` | HTTP 422 — request body fails schema or business validation |
| `code` | `unauthorized` | HTTP 401 — missing or invalid credentials |
| `code` | `rate_limited` | HTTP 429 — request rate exceeded |
| `code` | `method_not_allowed` | HTTP 405 — HTTP verb not supported on this path |
| `code` | `internal_error` | HTTP 500 — unexpected server error |
| `message` | String | Human-readable description; may be shown to end users |

**Implementation layers:**

1. **Controllers** — pattern-match context results and call private `err/1`
   helpers that produce the envelope. Each controller owns its error shapes.
2. **OpenApiSpex `CastAndValidate`** — validation failures from the request schema
   are rendered via `json_render_error_v2: true`, which produces a compatible
   shape that controllers then normalise.
3. **`YagyeCoreWeb.ErrorJSON`** — handles errors that escape controller dispatch
   (unmatched routes → 404, unhandled exceptions → 500). Returns the envelope
   for all status codes.

---

## Consequences

**Positive**
- Clients write one error-handling code path for all Yagye errors.
- SDK generation from the OpenAPI spec produces typed error models
  automatically.
- Support and monitoring are simplified — `error.type` immediately signals
  client vs server fault; `error.code` narrows the category.
- Familiar to developers already using Stripe.

**Negative / Trade-offs**
- Every controller must explicitly map context error tuples to the envelope.
  A missed pattern match (falling through to a generic 500) violates the
  contract. Code review must check error paths, not just happy paths.
- The envelope shape is an API surface contract. Changing field names or
  removing codes after public launch requires a versioned deprecation. This ADR
  must be superseded before any breaking change.
- In development (`debug_errors: true`), Phoenix shows its HTML debug page
  instead of the envelope for unmatched routes and crashes. This is dev-only
  behaviour and does not affect the production contract.
