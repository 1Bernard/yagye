# ADR-0020: ON DELETE RESTRICT and No Hard Deletes for All PSP Domain Records

**Date:** 2026-08-30
**Status:** Accepted

---

## Context

ADR-0009 established soft revocation for API credentials specifically. During
P13, the same question surfaced for routing rules, invoice line items, routing
actions, and routing conditions — child records whose parent might be
"deleted" in a naive CRUD sense.

The question generalises to the entire domain model: **should any PSP domain
record ever be physically removed from the database?**

### The financial audit trail requirement

In a PSP, every domain record is part of a financial audit trail:

- A **routing rule** governed which provider processed a payment. If the rule
  is deleted, post-hoc explanation of a routing decision becomes impossible.
- An **invoice line item** is the record of what was billed. Deleting it
  removes the billing evidence.
- A **payment attempt** is evidence that a charge was attempted. Deleting it
  hides failed charges.
- A **ledger entry** is the double-entry record of a financial movement.
  Deleting it breaks the accounting.

Regulatory frameworks — PCI-DSS, local central bank guidelines in the markets
Yagye operates in — require that financial records be available for audit for a
defined retention period (typically 5–7 years minimum).

### The cascade problem

Ecto's default `on_delete` behaviour for `references/2` is `:nothing`, which
in PostgreSQL means `NO ACTION` — effectively RESTRICT. However, several P13
migrations were initially written with `on_delete: :delete_all`, producing
`ON DELETE CASCADE` constraints. This is actively dangerous:

A single `Repo.delete(merchant)` would cascade to:
- `payments` → `payment_attempts` → `payment_events`
- `ledger_entries` → `ledger_postings`
- `invoices` → `invoice_line_items`
- `settlements` → `settlement_items`

An entire merchant's financial history could be destroyed in one statement,
with no application-layer protection. Migration `20260830000005` corrected all
five affected foreign keys from CASCADE to RESTRICT.

### Precedent from other PSPs

Stripe, Adyen, and Braintree do not expose delete endpoints for financial
records. The closest they offer is state transitions: void, refund, cancel.
This is the correct model for a PSP.

---

## Decision

**No PSP domain record is ever physically deleted. All foreign keys use
`ON DELETE RESTRICT`.**

### Foreign key rule

All `references` calls in Core migrations must specify `on_delete: :restrict`:

```elixir
add :invoice_id, references(:invoices, type: :uuid, on_delete: :restrict), null: false
```

For constraints added after table creation, use explicit SQL:

```sql
ALTER TABLE invoice_line_items
  ADD CONSTRAINT invoice_line_items_invoice_id_fkey
  FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT;
```

`ON DELETE RESTRICT` means the database itself will reject any attempt to
delete a parent row that has child rows. This is a defence-in-depth layer: even
if application code is wrong, the DB prevents audit-trail destruction.

### No `Repo.delete` on domain entities

No context function may call `Repo.delete/1` or `Repo.delete_all/1` on domain
entities. The correct alternatives by entity type:

| Entity type | Correct verb | Implementation |
|---|---|---|
| Routing rule | Deactivate | `Routing.deactivate_rule/1` sets `active: false` |
| API key | Revoke | `revoked_at = now()` (ADR-0009) |
| Invoice | Void | State machine transition to `"void"` |
| Payment | — | No delete, no void — immutable once created |
| Merchant | — | No delete — deactivation only (future) |
| Provider connection | Deactivate | `active: false` |

HTTP verbs map to state transitions, not deletion:

```
DELETE /internal/routing-rules/:id  →  :deactivate action (active: false)
DELETE /v1/merchants/:id/keys/:id   →  :revoke action (revoked_at = now())
```

### Permitted physical deletes

The following are **infrastructure records**, not domain records, and may be
physically deleted as part of normal housekeeping:

| Table | Who deletes | When |
|---|---|---|
| `oban_jobs` | Oban itself | After job completion + retention window |
| `idempotency_keys` | Scheduled cleanup job | After TTL expiry (default 24h) |
| `outbox_messages` | Outbox relay | After successful delivery |

These records are operational scaffolding, not financial evidence. Their
deletion does not break any audit trail.

### Active-record filtering

Queries on deactivatable entities must filter by `active = true` explicitly.
Partial indexes enforce this at the DB layer and document the intent:

```sql
CREATE INDEX routing_rules_active_mode_priority_index
  ON routing_rules (mode, priority)
  WHERE active = true;
```

Missing this filter is a **UX bug** (users see deactivated rules) but not a
security bug (unlike credential revocation, where the filter is a security
invariant). Both are bugs; only the severity differs.

---

## Consequences

### Positive

- **Complete, permanent audit trail.** Every routing decision, billing event,
  and ledger movement is always attributable and explainable, regardless of
  subsequent state changes.
- **DB-layer defence.** `ON DELETE RESTRICT` rejects orphaning attempts at the
  database level — catching bugs that bypass application-layer guards.
- **Regulatory compliance.** Financial records are retained for the full
  required audit period without a separate archival step.
- **Consistent with industry practice.** Stripe, Adyen, and Braintree follow
  the same principle.

### Negative / Trade-offs

- **Tables grow monotonically.** Deactivated routing rules, voided invoices,
  revoked keys — all remain as rows. Storage cost increases over time.
  Managed by archival partitioning at scale (see
  `docs/architecture/scaling-playbook.md`).
- **Queries must filter state explicitly.** Every list query on a
  deactivatable entity needs a `WHERE active = true` (or equivalent state
  filter). Omitting it returns stale records. Partial indexes and query
  objects in the portal enforce this by convention.
- **`ON DELETE RESTRICT` surfaces as a DB error.** If application code
  attempts to delete a parent row with children, PostgreSQL raises a foreign
  key violation. The application must handle this error gracefully — it
  should never reach the user as a 500.
- **No "undo" for revocation/deactivation.** Consistent with ADR-0009: once
  a record is deactivated, it is not reactivated. A new record is created if
  the merchant needs the capability again (e.g. a new API key).
