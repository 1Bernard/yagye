# ADR-0019: Cursor-Based (Keyset) Pagination for All Merchant-Facing List Endpoints

**Date:** 2026-08-30
**Status:** Accepted

---

## Context

Every merchant-facing list endpoint (payments, invoices, payouts, settlements,
customers, disputes, refunds) needs a pagination strategy. Three options exist:

**Offset pagination** (`?page=3&per_page=25` or `?offset=75&limit=25`):
Implemented in the initial drafts of every list context function. It has two
fundamental problems in a PSP:

1. **Performance**: `OFFSET N` requires PostgreSQL to scan and discard N rows
   before returning results. A merchant with 500,000 payments requesting page
   10,000 (`OFFSET 250,000`) triggers a near-full-table scan on every call.
   The problem compounds as the table grows — it cannot be solved by indexing
   alone, because the index must still be traversed to the offset point.

2. **Consistency**: the dataset is live. New payments arrive continuously. If a
   payment is inserted between a client's first and second page request, every
   subsequent page shifts by one row. A merchant integration doing automated
   reconciliation — fetching all payments since last run — can silently skip or
   double-count records. In a financial system, either failure is unacceptable.

**Page-number pagination** (Paystack, Flutterwave style — `?page=3`):
Presents a cleaner API surface but has identical underlying behaviour. The DB
query is still `OFFSET (page-1) * per_page`. The consistency and performance
problems remain; they are just less visible to the API consumer.

**Cursor-based (keyset) pagination** (Stripe style — `?starting_after=pay_…`):
The WHERE clause anchors to the last-seen record's identifier rather than a row
count. The DB query becomes `WHERE public_id < $cursor ORDER BY public_id DESC
LIMIT n`, which uses the B-tree index directly and is O(log n) regardless of
how many records exist before the cursor. Insertion of new records does not
affect pages already fetched.

The Shared.Pagination module was introduced in P13 to centralise this logic
across all list contexts.

---

## Decision

**All `/v1` merchant-facing list endpoints use cursor-based pagination.**

### Request parameters

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `limit` | integer | 25 | Capped at 100 server-side |
| `starting_after` | string | — | Fetch records older than this cursor |
| `ending_before` | string | — | Fetch records newer than this cursor |

`starting_after` and `ending_before` are mutually exclusive. Both are opaque
cursor strings — the `public_id` of the boundary record (or the internal `id`
UUID for entities without a `public_id`).

### Response envelope

```json
{
  "object": "list",
  "data": [ ... ],
  "has_more": true
}
```

`has_more: true` means there are more records in the traversal direction.
`total_count` is **never** exposed — it requires a `COUNT(*)` query against
a live table and gives API consumers false confidence in a number that changes
between requests.

### DB query shapes

**No cursor (first page):**
```sql
WHERE merchant_id = $1
ORDER BY public_id DESC
LIMIT n + 1
```

**`starting_after` (forward — older records):**
```sql
WHERE merchant_id = $1 AND public_id < $cursor
ORDER BY public_id DESC
LIMIT n + 1
```

**`ending_before` (backward — newer records):**
```sql
WHERE merchant_id = $1 AND public_id > $cursor
ORDER BY public_id ASC
LIMIT n + 1
```
Result is reversed in application code to restore newest-first order.

Fetching `n + 1` rows determines `has_more` without a COUNT query: if more
than `n` rows are returned, `has_more = true`; the extra row is not included
in `data`.

### Implementation

`YagyeCore.Shared.Pagination.paginate/3` accepts a base Ecto query, the cursor
field atom (`:public_id` or `:id`), and keyword opts. All list context functions
delegate to it:

```elixir
def list_payments(merchant_id, opts \\ []) do
  base = from(p in Payment, where: p.merchant_id == ^merchant_id)
  {:ok, Pagination.paginate(base, :public_id, opts)}
end
```

### Cursor field choice

`public_id` (UUIDv7 with type prefix, e.g. `pay_018e…`) is the cursor for all
entities that expose one. UUIDv7 is time-ordered, so lexicographic string
comparison in the WHERE clause produces correct chronological ordering.

`settlement_batches` and `account_verifications` have no `public_id`; their
internal `id` column (also UUIDv7, native `uuid` type) is used as the cursor.
These cursors are not type-prefixed, so clients cannot infer entity type from
them — documented as a known trade-off.

### Portal exception

The portal UI uses **Pagy (page-based pagination)** for human-facing lists.
This is intentional and correct:

- Page numbers convey position to a human operator ("page 3 of 12").
- Portal list queries always enforce a mandatory date-range filter (default:
  last 30 days), bounding the working set to a manageable size.
- Ops users browse records; they do not programmatically traverse the full
  dataset for reconciliation.

The distinction: cursor pagination is for **machine clients** traversing large,
live datasets; page pagination is for **humans** browsing a bounded filtered view.

---

## Consequences

### Positive

- **O(log n) query cost** regardless of dataset size — the index is traversed
  directly to the cursor point.
- **Stable results** during concurrent inserts — newly inserted records do not
  shift subsequent pages.
- **Stripe-compatible contract** — integrations familiar with Stripe's SDK can
  apply the same mental model.
- **No COUNT(*) overhead** — `has_more` is determined by fetching one extra row.
- **Single implementation** — `Shared.Pagination` is the only place this logic
  lives; adding a new list endpoint requires no new pagination code.

### Negative / Trade-offs

- **No random access** — clients cannot jump to page N without traversing from
  the beginning or a known cursor. Acceptable for reconciliation use cases;
  dashboard UIs use the portal instead.
- **No total count** — clients cannot display "showing 26–50 of 3,142". This is
  a deliberate choice. A total count on a live table is immediately stale.
- **`ending_before` is asymmetric** — it fetches in ASC order and reverses in
  application code. This is a source of implementation complexity that must be
  understood when extending `Shared.Pagination`.
- **Internal-id cursors are opaque** — for `settlement_batches` and
  `account_verifications`, the cursor is a raw UUID with no type prefix. Clients
  should treat all cursors as opaque strings regardless.
