# Double-Entry Ledger: Posting Flow

Last updated: 2026-10-18

```
DOUBLE-ENTRY LEDGER: POSTING FLOW DIAGRAMS
==========================================
Last updated: 2026-10-18

ACCOUNT TYPES
─────────────

  float_account     — Yagye's MoMo/bank float. Increases when funds arrive
                      from the provider. Decreases on settlement payout.

  merchant_payable  — Liability to a specific merchant. Increases when a
                      payment succeeds (net of fee). Decreases on settlement.

  fee_payable       — Yagye's accrued revenue. Increases on every payment.
                      Decreases when Yagye withdraws its own earnings.

  reserve_account   — Withheld rolling reserve (risk buffer). Increases
                      when reserve is withheld. Decreases on reserve release.

  bank_payable      — Staging account: funds moved here before bank wire.
                      Increases at sweep. Decreases when wire is sent.

  suspense          — Temporary holding. Used when funds arrive before
                      they can be definitively attributed.

KEY INVARIANT: At every COMMIT, SUM(all debits) = SUM(all credits).
              Enforced by a DEFERRABLE INITIALLY DEFERRED trigger.

──────────────────────────────────────────────────────────────────────────────

SCENARIO 1: SUCCESSFUL MOBILE MONEY PAYMENT
  Merchant: Kofi's Shop    Amount: GHS 100.00 (10000 pesewas)    Fee: 2.50%

STEP 1 — MoMo callback received (funds arrived in Yagye's float):

  Entry:  payment_receipt
  ┌─────────────────────┬───────────┬───────────┐
  │ Account             │ Debit     │ Credit    │
  ├─────────────────────┼───────────┼───────────┤
  │ suspense            │ 10,000    │           │   ← holding until confirmed
  │ float_account       │           │ 10,000    │   ← funds landed
  └─────────────────────┴───────────┴───────────┘
  Sum: 10,000 = 10,000 ✓

STEP 2 — Funds allocated to merchant (net of fee):

  Entry:  fee_and_allocation
  ┌─────────────────────┬───────────┬───────────┐
  │ Account             │ Debit     │ Credit    │
  ├─────────────────────┼───────────┼───────────┤
  │ float_account       │ 10,000    │           │   ← float reduced
  │ merchant_payable    │           │  9,750    │   ← GHS 97.50 net
  │ fee_payable         │           │    250    │   ← GHS 2.50 Yagye fee
  └─────────────────────┴───────────┴───────────┘
  Sum: 10,000 = 10,000 ✓

Running balance after payment.succeeded:
  float_account:    +10,000 - 10,000 =      0 (net zero on float — allocated)
  merchant_payable:           +9,750 = +9,750 (owes merchant)
  fee_payable:                  +250 =   +250 (Yagye earned)
  suspense:        +10,000            +10,000 (will clear in recon)

──────────────────────────────────────────────────────────────────────────────

SCENARIO 2: SETTLEMENT SWEEP (daily)
  Merchant payable: GHS 97.50 (9,750 pesewas) — accumulated across all payments

STEP 3 — Sweep: merchant_payable → bank_payable:

  Entry:  settlement_sweep
  ┌─────────────────────┬───────────┬───────────┐
  │ Account             │ Debit     │ Credit    │
  ├─────────────────────┼───────────┼───────────┤
  │ merchant_payable    │  9,750    │           │   ← liability cleared
  │ bank_payable        │           │  9,750    │   ← staged for wire
  └─────────────────────┴───────────┴───────────┘
  Sum: 9,750 = 9,750 ✓

STEP 4 — Bank wire dispatched:

  Entry:  bank_disbursement
  ┌─────────────────────┬───────────┬───────────┐
  │ Account             │ Debit     │ Credit    │
  ├─────────────────────┼───────────┼───────────┤
  │ bank_payable        │  9,750    │           │   ← staging cleared
  │ float_account       │           │  9,750    │   ← float reduced by payout
  └─────────────────────┴───────────┴───────────┘
  Sum: 9,750 = 9,750 ✓

Running balance after settlement:
  float_account:    0 + 0 - 9,750 = -9,750   (Yagye paid out from float)
  merchant_payable: 9,750 - 9,750 =      0   (liability cleared)
  bank_payable:     9,750 - 9,750 =      0   (staging cleared)
  fee_payable:                     =   +250   (Yagye keeps the fee)

  Net across ALL accounts: -9,750 + 0 + 0 + 250 + ... ← still balanced

──────────────────────────────────────────────────────────────────────────────

SCENARIO 3: ROLLING RESERVE WITHHOLDING
  Reserve rate: 5% for 30 days   Amount: GHS 5.00 (500 pesewas) on GHS 100 payment

STEP 2 (modified) — Allocation with reserve:

  Entry:  fee_and_allocation_with_reserve
  ┌─────────────────────┬───────────┬───────────┐
  │ Account             │ Debit     │ Credit    │
  ├─────────────────────┼───────────┼───────────┤
  │ float_account       │ 10,000    │           │
  │ merchant_payable    │           │  9,250    │   ← net after fee and reserve
  │ fee_payable         │           │    250    │   ← 2.5% fee
  │ reserve_account     │           │    500    │   ← 5% reserve
  └─────────────────────┴───────────┴───────────┘
  Sum: 10,000 = 10,000 ✓

AFTER 30 DAYS — Reserve release:

  Entry:  reserve_release
  ┌─────────────────────┬───────────┬───────────┐
  │ Account             │ Debit     │ Credit    │
  ├─────────────────────┼───────────┼───────────┤
  │ reserve_account     │    500    │           │   ← reserve cleared
  │ merchant_payable    │           │    500    │   ← returned to merchant
  └─────────────────────┴───────────┴───────────┘
  Sum: 500 = 500 ✓

──────────────────────────────────────────────────────────────────────────────

SCENARIO 4: CORRECTION VIA REVERSING ENTRY
  An incorrect fee was posted. The original entry must not be deleted.
  All corrections use REVERSING ENTRIES — the audit trail is never modified.

ORIGINAL (wrong fee — 5% instead of 2.5%):

  Entry:  wrong_allocation  (entry_id = abc-123)
  ┌─────────────────────┬───────────┬───────────┐
  │ float_account       │ 10,000    │           │
  │ merchant_payable    │           │  9,500    │   ← WRONG (should be 9,750)
  │ fee_payable         │           │    500    │   ← WRONG (should be 250)
  └─────────────────────┴───────────┴───────────┘

REVERSAL (inverts the original):

  Entry:  reversal_of_abc-123  (reverses_entry_id = abc-123)
  ┌─────────────────────┬───────────┬───────────┐
  │ float_account       │           │ 10,000    │   ← mirror image
  │ merchant_payable    │  9,500    │           │
  │ fee_payable         │    500    │           │
  └─────────────────────┴───────────┴───────────┘

CORRECTION (correct amounts):

  Entry:  corrected_allocation
  ┌─────────────────────┬───────────┬───────────┐
  │ float_account       │ 10,000    │           │
  │ merchant_payable    │           │  9,750    │
  │ fee_payable         │           │    250    │
  └─────────────────────┴───────────┴───────────┘

All three entries remain in ledger_postings. The net effect is correct.
The original entry is preserved for audit.

──────────────────────────────────────────────────────────────────────────────

DATABASE SCHEMA (simplified):

  ledger_entries
  ├── id (uuid)
  ├── source_type + source_id      ← "payment", "pay_018e..."
  ├── entry_type                   ← "payment_receipt", "fee_and_allocation"
  ├── effective_at (domain date)   ← when it happened
  ├── recorded_at (system date)    ← when DB row was inserted
  └── reverses_entry_id            ← if this is a correction

  ledger_postings  (bigserial PK — not UUID, for watermarking)
  ├── id bigserial                 ← dense, ordered, used as watermark
  ├── entry_id → ledger_entries
  ├── account_id → ledger_accounts
  ├── direction   ('debit' | 'credit')
  ├── amount      bigint > 0       ← always positive; direction carries sign
  └── merchant_id                  ← denormalized for fast balance queries

  ledger_balances  (cache, not truth)
  ├── account_id
  ├── balance bigint
  └── last_posting_id              ← watermark: balance is correct for id <= this
```
