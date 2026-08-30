# Domain Model

This directory documents the bounded contexts, aggregates, and domain concepts
in the Yagye platform. Each file covers one bounded context.

## Bounded contexts

| Context | Module | Description |
|---|---|---|
| Payments | `YagyeCore.Payments` | Payment lifecycle, dispatch, events |
| Merchants | `YagyeCore.Merchants` | Merchant onboarding, API keys, mode |
| Compliance | `YagyeCore.Compliance` | KYB, beneficial owners, documents |
| Customers | `YagyeCore.Customers` | Customer records, KYC tiers, account verifications |
| Disputes | `YagyeCore.Disputes` | Disputes and refunds |
| Invoices | `YagyeCore.Invoices` | Invoice lifecycle and delivery |
| Routing | `YagyeCore.Routing` | Payment routing rules (platform + merchant scope) |
| Ledger | `YagyeCore.Ledger` | Double-entry ledger accounts, postings, balances |
| Settlement | `YagyeCore.Settlement` | Settlement batches, settlement matching |
| Payouts | `YagyeCore.Payouts` | Merchant payout destinations and payout jobs |
| Reserves | `YagyeCore.Reserves` | Merchant reserve holds |
| FX | `YagyeCore.FX` | Exchange rates |
| Float | `YagyeCore.Float` | MoMo float balances |
| Providers | `YagyeCore.Providers` | PSP provider registry, credentials |
| Reconciliation | `YagyeCore.BankReconciliation` | Bank statement import and matching |
| Webhooks | `YagyeCore.Webhooks` | Outbound webhook events |

## Key invariants

- **No hard deletes.** All domain records are deactivated, voided, or revoked —
  never physically removed. See ADR-0020.
- **Mode isolation.** Every domain record carries `mode: simulation | sandbox | live`.
  Records in one mode are never visible to or affected by another mode.
- **Double-entry ledger.** Every money movement produces balanced ledger postings.
  The sum of all postings across all accounts is always zero. See ADR-0005.
- **Idempotency on writes.** Mutation endpoints require an `Idempotency-Key` header.
  Replaying the same request returns the same response without re-executing side
  effects. See ADR-0008.

## Files in this directory

Add one file per bounded context as the domain model is documented:

- `payments.md` — state machine, events, provider dispatch
- `routing.md` — rule evaluation, dual-scope model
- `invoices.md` — state machine, line items, delivery
- `ledger.md` — account types, posting rules, balance computation
- `compliance.md` — KYB flow, UBO rules, screening
