# ADR-0009: Soft Revocation — No Hard Deletes for Credentials

**Date:** 2026-08-18
**Status:** Accepted

---

## Context

API keys and other credentials are both **security artifacts** and **financial
audit artifacts**. When a merchant reports a suspicious transaction, the first
question is "which key authorised it?" If the key has been hard-deleted, the
audit trail is broken.

Regulatory frameworks (PCI-DSS, PSD2) require that access logs remain
attributable to the credential that authorised each action. This is impossible
if credentials can be physically removed from the database.

Additionally, HTTP `DELETE` as a verb carries semantic ambiguity: does "delete
an API key" mean "revoke it immediately" or "erase it from existence"? In
payment APIs, the correct meaning is always the former.

Stripe, Braintree, and Adyen all use soft revocation for API credentials.

---

## Decision

**HTTP `DELETE` on a credential means revocation, not physical deletion.**

The row is never removed from the database. Revocation sets a timestamp:

```
DELETE /v1/merchants/:merchant_id/keys/:key_id
→ sets api_keys.revoked_at = now()
→ returns the key with revoked_at populated (200 OK)
```

**Rules that follow from this decision:**

1. **No `Repo.delete` on credential entities.** Any context function that would
   physically delete a credential is a bug.
2. **Active-key queries filter by `revoked_at IS NULL`.** The `authenticate/1`
   function rejects any key with `revoked_at IS NOT NULL`.
3. **Revocation is immediate and permanent.** There is no "undo revocation" — if
   a merchant needs a new key, they issue a new one.
4. **The principle extends to all credential-bearing entities.** API keys
   established the pattern; future entities (webhook signing secrets,
   OAuth tokens, etc.) must follow it.

A second `DELETE` on an already-revoked key returns `404 Not Found` (not `200`)
because the active resource no longer exists — consistent with how a `GET` on a
revoked key would behave.

---

## Consequences

**Positive**
- Complete, permanent audit trail: every authorised action is attributable to
  the key that performed it, even after the key is revoked.
- Supports incident response: "list all requests made by this key before
  revocation" is always answerable.
- Consistent with industry practice (Stripe, Braintree, Adyen).

**Negative / Trade-offs**
- The `api_keys` table grows monotonically. This is acceptable — key issuance is
  infrequent and the rows are small.
- Active-key queries must always include `WHERE revoked_at IS NULL`. Missing this
  filter is a security bug. A partial index on `api_keys (key_prefix) WHERE
  revoked_at IS NULL` makes this fast and documents the intent.
- The semantics of `DELETE` returning `200` (with the revoked resource) rather
  than `204` (empty) must be documented for SDK consumers.
