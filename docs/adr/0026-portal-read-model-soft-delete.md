# ADR-0026: Soft-Delete on Portal Read Models for JOIN Preservation

**Date:** 2026-09-22
**Status:** Accepted

---

## Context

ADR-0009 established that credentials in Core (API keys, webhook signing
secrets) are never hard-deleted — only soft-revoked. ADR-0020 extended
this to all PSP data tables via `RESTRICT` foreign keys.

The Portal is a **read model** — its tables are projections of Core events,
not sources of truth. The question of deletion is different here:

When a merchant removes a webhook endpoint, Core deletes the
`merchant_webhook_endpoints` row (the routing table entry is no longer
needed). Core publishes a `webhook.endpoint.deregistered` event. The Portal's
`WebhookEventsConsumer` receives this event and must decide what to do with
the `portal_webhook_endpoints` row.

**The problem with hard-deleting the Portal row:**

`portal_webhook_deliveries` has a foreign key on `endpoint_id`. Delivery
records are retained for 30 days (their own retention policy). Hard-deleting
the endpoint row would either:
- Cascade-delete all delivery records for that endpoint (losing audit history
  before the 30-day window expires), or
- Prevent the delete due to a `RESTRICT` foreign key (the row cannot be
  removed while deliveries reference it).

Even if the FK constraint is relaxed: without the endpoint row, the delivery
log drawer cannot resolve the URL the event was sent to — degrading the
developer's ability to diagnose past failures.

**Why this is different from ADR-0009:**

ADR-0009 is about preserving credential audit trails in the **write model**
for regulatory and security purposes. This ADR is about preserving **JOIN
resolution** in the read model so the developer console stays useful after
an endpoint is removed. The motivation is operational rather than regulatory.

---

## Decision

**Portal read model rows that are referenced by delivery logs use soft-delete
rather than hard-delete. The row is marked with `deleted_at` and hidden from
the active list via an explicit `kept` scope.**

Concretely for `portal_webhook_endpoints`:

```ruby
scope :kept, -> { where(deleted_at: nil) }

def soft_delete!
  update!(deleted_at: Time.current, active: false)
end
```

`WebhookEventsConsumer#delete_endpoint` calls `soft_delete!` instead of
`destroy`. The controller's `destroy` action also calls `soft_delete!`.

**Rules that follow from this decision:**

1. **Use `scope :kept` explicitly, not `default_scope`.** `default_scope`
   silently filters every query including upserts, admin lookups, and
   association preloads — it causes subtle bugs when an endpoint is
   re-registered after deletion (the upsert would appear to succeed but the
   row stays hidden). Explicit `.kept` makes the filter visible at the call site.

2. **Re-registration clears `deleted_at`.** The upsert in `upsert_endpoint`
   includes `deleted_at: nil` so that if a merchant removes and re-adds an
   endpoint with the same `endpoint_id`, the record becomes visible again
   without requiring a manual DB fix.

3. **Delivery log associations bypass the scope.** `portal_webhook_deliveries`
   `belongs_to :portal_webhook_endpoint` does not apply `.kept` — delivery
   records must be able to JOIN soft-deleted endpoints to display the URL.

4. **The principle applies to any Portal read model table that is referenced
   by a delivery or audit log.** Future tables in the same position (e.g.
   portal API key records once delivery history references them) should follow
   the same pattern.

---

## Consequences

### Positive
- Delivery log entries for removed endpoints continue to show the endpoint URL,
  event type, attempt count, and response status — the developer console
  remains useful for post-mortem investigation.
- Re-registration of a previously-removed endpoint works without data
  inconsistency.
- The explicit `kept` scope makes the filtering intent visible and avoids the
  `default_scope` anti-pattern.

### Negative / Trade-offs
- Soft-deleted rows accumulate in `portal_webhook_endpoints`. A background job
  to prune rows where `deleted_at` is older than the delivery log retention
  window (30 days) will be needed at production scale.
- Every query that lists active endpoints must explicitly call `.kept`. Missing
  it shows deleted endpoints to the merchant — a UX bug, not a security one.
  A linter rule or test helper that asserts `.kept` is called for merchant-
  visible lists would prevent this.

### Relationship to other ADRs
- **ADR-0009**: Credential revocation in Core's write model (regulatory/audit
  obligation). This ADR is about JOIN preservation in the Portal read model
  (operational, not regulatory).
- **ADR-0020**: No hard deletes on PSP write-model tables. The Portal read
  model is not a PSP write table; soft-delete here is chosen for JOIN
  preservation, not referential integrity on the financial record.
