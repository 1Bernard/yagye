# ADR-0002: Integer Minor Units for Monetary Values

**Date:** 2026-08-17
**Status:** Accepted

## Context

Yagye processes payment amounts — charges, settlements, refunds, fee splits.
Monetary arithmetic done carelessly loses money: `0.1 + 0.2` in IEEE 754 floating
point is `0.30000000000000004`, not `0.3`. In a payments system, this is not a
rounding curiosity — it is a regulatory and reconciliation risk.

Three representation options were considered:

**Option A — Float (`float`)**: native Elixir `float` / PostgreSQL `float8`.
Fast arithmetic, but IEEE 754 binary fractions cannot represent many decimal values
exactly. Unacceptable for financial work.

**Option B — Decimal (`Decimal` library)**: arbitrary-precision decimal arithmetic.
Exact, but requires a dependency, the type is not a primitive, and arithmetic
functions must be called explicitly (`Decimal.add/2` etc.).

**Option C — Integer minor units**: store amounts as integers in the smallest
currency unit (cents for USD, pesewas for GHS, pence for GBP). A payment of
$12.50 USD is stored as `1250`. Currency is carried as an ISO-4217 string
alongside the amount.

## Decision

All monetary values in Yagye are represented as **integer minor units** paired
with an **ISO-4217 currency code** string, encapsulated in `Yagye.Money`:

```elixir
%Yagye.Money{amount: 1250, currency: "USD"}  # $12.50
```

Addition, subtraction, and comparison are exact integer arithmetic.
Allocation (splitting an amount into parts) uses the **largest-remainder algorithm**
(`Yagye.Money.allocate/2`) to ensure every minor unit is accounted for — no cent
is created or destroyed.

## Consequences

### Positive
- Zero floating-point error: all arithmetic is integer arithmetic.
- Natural PostgreSQL storage as `bigint`; no special column type or extension needed.
- The struct is a plain Elixir value — no external dependency for the core type.
- `allocate/2` with the largest-remainder algorithm guarantees conservation:
  `sum(parts) == original` always, proved by StreamData property tests.
- Amounts travel across service boundaries as integers in JSON with no precision loss.

### Negative / Trade-offs
- Displaying a human-readable amount requires knowing the currency's decimal places
  (USD has 2; JPY has 0; KWD has 3). A formatting layer is needed for UI/API output.
- Cross-currency arithmetic is intentionally prevented at compile time (pattern
  matching on currency codes). Currency conversion is an explicit domain operation,
  not an automatic one.
- `Yagye.Money` does not validate that the currency code is a real ISO-4217 code.
  That is an application-layer concern (changeset validation on input).
