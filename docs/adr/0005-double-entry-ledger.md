# ADR-0005: Double-Entry Ledger as the Accounting Model

**Date:** 2026-08-17
**Status:** Accepted

## Context

Yagye moves money: it collects from payers, holds funds in float accounts, pays out
to merchants, deducts fees, and reconciles against gateway settlement files. Any
system that moves money must answer two questions with certainty:

1. Where is every minor unit at any point in time?
2. How did it get there?

Two accounting models were considered:

**Option A — Running balance**: each account stores a single `balance` column.
A payment debits one row and credits another. Simple to implement; fast to read.
The problem: a balance is a snapshot. If a bug or race condition corrupts it,
there is no way to reconstruct the correct value — the history is gone. Running
balances fail audits.

**Option B — Double-entry ledger**: every movement of money is recorded as a pair
of journal entries — one debit and one credit — so that debits always equal credits
across the system. Balances are derived by summing entries, not stored. The ledger
is append-only; nothing is ever updated or deleted.

Double-entry bookkeeping has been the standard for financial accounting since the
15th century. Every regulated payment institution uses it.

## Decision

All financial state in Yagye is stored in a **double-entry ledger**:

- Every transaction produces one or more **journal entries** (debit/credit pairs).
- Each entry records: account, direction (debit/credit), amount, currency,
  timestamp, and a reference to the originating transaction.
- **Balances are never stored** — they are always computed as `SUM(credits) - SUM(debits)`
  over the relevant entries.
- The `journal_entries` table is append-only. No row is ever updated or deleted.
- Account types follow standard accounting conventions:
  - Asset and expense accounts: debit increases, credit decreases.
  - Liability, equity, and revenue accounts: credit increases, debit decreases.

This model will be implemented in `yagye_core` starting in Phase 1 (Merchants &
Onboarding) and extended through Phase 4 (Settlements) and Phase 5 (Reconciliation).

## Consequences

### Positive
- The ledger is self-auditing: `SUM(all debits) == SUM(all credits)` is a
  constraint that can be asserted at any time and at any granularity.
- Any balance can be reconstructed from scratch by replaying the journal entries,
  regardless of how many bugs have been fixed in the interim.
- Regulatory reporting and external audits can be satisfied by querying the ledger
  directly — no separate reporting tables needed.
- Concurrent writes are safe: inserts to `journal_entries` do not require
  read-modify-write cycles, eliminating a class of race conditions that plague
  running-balance designs.

### Negative / Trade-offs
- Querying a current balance requires aggregation (`SUM`), not a single column read.
  Materialised views or periodic snapshots may be needed for performance at scale
  (deferred to Phase 5+).
- The schema is more complex than a simple `accounts.balance` column. Every
  transaction requires careful construction of the correct debit/credit pair.
- Developers unfamiliar with double-entry bookkeeping require onboarding before
  contributing to ledger-touching code. Domain knowledge cannot be assumed.
