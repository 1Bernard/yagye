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
%Yagye.Money{amount: 1250, currency: "GHS"}  # GHS 12.50 (pesewas)
%Yagye.Money{amount: 1250, currency: "JPY"}  # ¥1,250 (yen has no sub-unit)
```

**Why `"USD"` and not `"cents"`?**

`currency` stores the ISO-4217 major-unit code, not the name of the minor unit.
The major-unit code is all you need: ISO-4217 defines the decimal exponent for
every currency (`USD` → 2 → divide by 100; `JPY` → 0 → divide by 1; `KWD` → 3
→ divide by 1000). Storing `"cents"` or `"USD_CENTS"` would break this lookup and
make the type useless for currencies other than USD.

The rule is: **`amount` is always in the smallest unit; `currency` always names the
major unit.** The formatting layer does the shift when displaying to humans.

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
- A formatting layer is required for display: `format_money(1250, currency: "GHS")` →
  `"GHS 12.50"`. The decimal shift (÷100 for GHS, ÷1 for JPY, ÷1000 for KWD) is
  derived from ISO-4217 at render time, not stored with the amount.
- Cross-currency arithmetic is intentionally prevented at compile time (pattern
  matching on currency codes). Currency conversion is an explicit domain operation,
  not an automatic one.
- `Yagye.Money` does not validate that the currency code is a real ISO-4217 code.
  That is an application-layer concern (changeset validation on input).
