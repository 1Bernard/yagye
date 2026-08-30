# ADR-0021: Dual-Scope Routing Rules — Platform and Merchant

**Date:** 2026-08-30
**Status:** Accepted

---

## Context

Yagye operates under two business models that must coexist in the routing layer:

**Model A — PSP (current):** Yagye is the payment service provider. All
merchants route through Yagye's infrastructure. Yagye's ops team decides which
payment provider (MTN MoMo, Vodafone Cash, Stripe, Flutterwave, Paystack, etc.)
handles each payment, based on cost, reliability, network coverage, and mode.
Merchants have no visibility into or control over this decision.

**Model B — Orchestration (P16+):** Large enterprise merchants (gated by
entitlement) bring their own provider relationships and want to control how
their payments are routed — preferring a specific provider for certain
currencies, falling back to another on failure, or splitting volume by
percentage. This is the "orchestration layer" positioning described in the
product roadmap.

Both models must be supported by the same routing infrastructure. Building Model
B on top of a Model A-only schema would require a breaking migration at P16.
The P13 design was therefore made P16-ready from the start.

### Why not two separate tables?

An earlier sketch used `platform_routing_rules` and `merchant_routing_rules` as
separate tables. The evaluation logic would query both and merge. Problems:

- Duplicate schema maintenance — any change to rule structure (new condition
  type, new action field) must be made in two places.
- Evaluation order is an application-layer convention rather than a DB-level
  invariant.
- Cross-scope analytics (e.g. "what percentage of platform rules have been
  overridden by merchant rules?") require joins across tables.

A single `routing_rules` table with a `scope` discriminator was chosen instead.

### The NULLS DISTINCT problem

A naive composite unique index on `(scope, merchant_id, mode, priority)` does
not enforce platform-scope uniqueness. In standard SQL, `NULL ≠ NULL`, so two
rows with the same `(mode, priority)` and `merchant_id = NULL` do not conflict.
PostgreSQL 15 introduced `NULLS NOT DISTINCT`, but for compatibility and
clarity, the solution is two **partial unique indexes** — one per scope.

---

## Decision

**`routing_rules` has a `scope` column (`platform | merchant`) and is evaluated
in two phases: merchant-scope first, platform-scope as fallback.**

### Schema

```
routing_rules
  id          uuid  PK
  scope       text  CHECK (scope IN ('platform', 'merchant'))
  merchant_id uuid  REFERENCES merchants(id) ON DELETE RESTRICT — NULL for platform scope
  mode        text  CHECK (mode IN ('simulation', 'sandbox', 'live'))
  name        text
  priority    integer
  active      boolean  DEFAULT true
  inserted_at utc_datetime_usec
  updated_at  utc_datetime_usec

  CHECK: scope = 'platform' → merchant_id IS NULL
  CHECK: scope = 'merchant' → merchant_id IS NOT NULL
```

Child tables: `routing_rule_conditions` (JSONB field/operator/value per rule)
and `routing_rule_actions` (provider_id + priority per rule).

### Uniqueness enforcement

Two partial unique indexes replace the single composite index:

```sql
-- Platform: no two platform rules may share (mode, priority)
CREATE UNIQUE INDEX routing_rules_platform_mode_priority_index
  ON routing_rules (mode, priority)
  WHERE merchant_id IS NULL AND scope = 'platform';

-- Merchant: no two rules for the same merchant may share (mode, priority)
CREATE UNIQUE INDEX routing_rules_merchant_mode_priority_index
  ON routing_rules (merchant_id, mode, priority)
  WHERE merchant_id IS NOT NULL AND scope = 'merchant';
```

### Evaluation algorithm

`Routing.evaluate(merchant_id, mode, payment_attrs)`:

1. Load all **active, merchant-scope** rules for `(merchant_id, mode)`, ordered
   by ascending `priority`.
2. Evaluate each rule's conditions against `payment_attrs`. Return the first
   matching rule's action (`provider_id`).
3. If no merchant rule matches (or merchant has no rules), load all **active,
   platform-scope** rules for `mode`, ordered by ascending `priority`.
4. Evaluate and return the first matching rule's action.
5. If nothing matches, return `{:error, :no_route}`.

Lower `priority` integer = higher precedence (priority 1 is evaluated first).

### Condition value shape

Condition values use a JSONB envelope `{"v": value}` rather than a raw scalar:

```json
{ "field": "amount", "operator": "gte", "value": {"v": 50000} }
```

The `{"v": ...}` wrapper allows future multi-value conditions (`{"v": [1, 2,
3]}` for `in` operators) and range conditions without a schema change. It is
enforced by the `apply_operator/3` function in `YagyeCore.Routing`.

### API surfaces

| Scope | API | Auth |
|---|---|---|
| Platform | `GET/POST /internal/routing-rules` | X-Service-Token (ops portal → core) |
| Platform | `GET /internal/routing-rules/:id` | X-Service-Token |
| Platform | `POST /internal/routing-rules/:id/deactivate` | X-Service-Token |
| Merchant | `/v1/routing-rules` (P16) | Bearer API key, entitlement-gated |

Platform rules are never exposed to merchants. Merchant rules are never exposed
to other merchants or to the ops portal without explicit scoping.

---

## Consequences

### Positive

- **P16-ready schema.** Merchant routing is enabled at P16 by unlocking the
  entitlement and exposing the `/v1/routing-rules` controller — no migration
  required.
- **Isolation.** A misconfigured merchant rule cannot affect other merchants.
  Merchant rules are filtered by `merchant_id` before evaluation begins.
- **Ops control.** Yagye ops manages all platform rules today. Merchant rules
  layer on top without displacing the platform defaults — if a merchant rule
  matches, it wins; otherwise the platform rule governs.
- **Single schema.** Rule structure changes (new condition operators, new
  action fields) are made once and apply to both scopes.
- **JSONB condition values** accommodate future operator types (`in`, range,
  regex) without schema migrations.

### Negative / Trade-offs

- **Two-phase evaluation** adds a small latency overhead. In the Model A case
  (no merchant rules), phase 1 executes a query that returns zero rows before
  falling through to phase 2. At current volumes this is negligible; at very
  high volume it can be eliminated by caching the active rule set in ETS with
  a short TTL (a P17-area optimisation, not needed now).
- **Priority integers require coordination.** If two ops users add platform
  rules with the same mode and priority simultaneously, one will receive a
  unique constraint error. Ops tooling should surface available priority slots
  before rule creation.
- **Partial index complexity.** The two-index approach is less obvious than a
  single composite index. The reason (NULLS DISTINCT behaviour in standard SQL
  unique indexes) is documented in migration `20260830000004` and in this ADR.
