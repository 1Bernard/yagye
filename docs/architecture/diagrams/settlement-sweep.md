# Settlement Sweep and Disbursement

Last updated: 2026-10-18

```
SETTLEMENT SWEEP AND DISBURSEMENT
===================================
Last updated: 2026-10-18

PURPOSE: Move accumulated merchant payables from Yagye's ledger
         into the merchant's bank account, with SoD approval and
         immutable net_amount locking.

──────────────────────────────────────────────────────────────────────────────

SETTLEMENT LIFECYCLE:

  Phase 1: ELIGIBILITY SCAN
  Phase 2: BATCH CREATION (net_amount locked)
  Phase 3: SoD APPROVAL (approver ≠ creator)
  Phase 4: DISPATCH (bank wire initiated)
  Phase 5: RECONCILIATION (verify wire landed)

──────────────────────────────────────────────────────────────────────────────

PHASE 1: ELIGIBILITY SCAN (SettlementSweepWorker — daily cron)

  ┌───────────────────────────────────────────────────────────────────┐
  │  SELECT                                                            │
  │    lp.merchant_id,                                                │
  │    SUM(CASE WHEN lp.direction = 'credit' THEN lp.amount           │
  │             ELSE -lp.amount END) AS gross_payable                 │
  │  FROM ledger_postings lp                                          │
  │  JOIN ledger_accounts la ON la.id = lp.account_id                │
  │  WHERE la.type = 'merchant_payable'                               │
  │    AND lp.mode = 'live'           ← never settle simulation       │
  │    AND lp.settled_at IS NULL      ← not yet swept                 │
  │    AND lp.effective_at < today    ← completed business day        │
  │  GROUP BY lp.merchant_id                                          │
  │  HAVING SUM(...) >= minimum_settlement_threshold                  │
  └───────────────────────────────────────────────────────────────────┘
                     │
                     │  For each eligible merchant:
                     ▼
  PHASE 2: BATCH CREATION

  ┌───────────────────────────────────────────────────────────────────┐
  │  Ecto.Multi:                                                       │
  │    INSERT settlement_batches                                       │
  │      merchant_id        = mch_018e...                             │
  │      gross_amount       = 9,750        ← sum of eligible postings │
  │      platform_fees      = 250          ← sum of fee_payable rows  │
  │      net_amount         = 9,500        ← LOCKED. Immutable.       │
  │      state              = 'pending_approval'                      │
  │      period_start       = yesterday 00:00                         │
  │      period_end         = yesterday 23:59                         │
  │      created_by         = system (SettlementSweepWorker)          │
  │                                                                   │
  │    INSERT ledger_entries: settlement_sweep                        │
  │    INSERT ledger_postings:                                        │
  │      DR merchant_payable    9,500                                 │
  │      CR bank_payable        9,500                                 │
  │                                                                   │
  │    UPDATE ledger_postings                                         │
  │      SET settled_at = NOW()                                       │
  │      WHERE id IN (eligible_posting_ids)                           │
  └───────────────────────────────────────────────────────────────────┘

WHY IS net_amount LOCKED?

  net_amount is set once at batch creation and never changes.
  If pricing changes after batch creation, the settled amount
  is not retroactively adjusted.

  BankDispatchWorker reads net_amount at dispatch time.
  Settlement = what was owed at sweep time, not at dispatch time.

──────────────────────────────────────────────────────────────────────────────

PHASE 3: SoD APPROVAL (Segregation of Duties)

  ┌──────────────────────────────────────────────────────────────────┐
  │  Ops manager reviews the settlement batch in the portal.          │
  │                                                                  │
  │  settlement_batches DB CHECK:                                    │
  │    CHECK (dispatch_approved_by IS NULL                           │
  │           OR dispatch_approved_by IS DISTINCT FROM created_by)  │
  │                                                                  │
  │  The person who created the batch (SettlementSweepWorker = system)│
  │  is technically "created_by = system_user".                      │
  │  In practice: two human eyes must review before approval.        │
  │                                                                  │
  │  Approval:                                                       │
  │    PATCH /internal/settlement-batches/:id/approve                │
  │    Body: { approved_by: ops_manager_id }                         │
  │                                                                  │
  │  Rejection:                                                      │
  │    PATCH /internal/settlement-batches/:id/reject                 │
  │    Body: { rejected_by: ops_manager_id, reason: "..." }          │
  │                                                                  │
  │  DB enforces: rejected_by IS DISTINCT FROM created_by            │
  └──────────────────────────────────────────────────────────────────┘
                     │
                     │  approved
                     ▼
  PHASE 4: DISPATCH

  ┌──────────────────────────────────────────────────────────────────┐
  │  BankDispatchWorker (Oban job, triggered on approval)            │
  │                                                                  │
  │  1. Fetch settlement_batch                                       │
  │     Assert mode = 'live'  (never dispatch simulation batches)   │
  │     Assert state = 'approved'                                    │
  │     Use net_amount (immutable)                                   │
  │                                                                  │
  │  2. Initiate bank wire (via bank API or manual process at P13)   │
  │                                                                  │
  │  3. Update settlement_batches:                                   │
  │     state = 'dispatched'                                         │
  │     dispatch_approved_by = ops_manager_id                        │
  │     dispatch_approved_at = NOW()                                 │
  │                                                                  │
  │  4. Insert ledger_postings:                                      │
  │     DR bank_payable     9,500                                    │
  │     CR float_account    9,500     ← float reduced by payout     │
  └──────────────────────────────────────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

FULL LEDGER TRACE FOR ONE SETTLEMENT:

  Merchant: Kofi's Shop
  Eligible payments this period: 10 × GHS 100 = GHS 1,000 gross
  Fee: 2.5% = GHS 25 total fees
  Net to merchant: GHS 975

  ENTRIES:
  ┌────────────────────────────┬──────────────────────────────────────────┐
  │ Event                      │ Ledger Postings                          │
  ├────────────────────────────┼──────────────────────────────────────────┤
  │ 10 × payment.succeeded     │ DR float_acct    100,000                 │
  │                            │ CR merch_payable  97,500                 │
  │                            │ CR fee_payable     2,500                 │
  ├────────────────────────────┼──────────────────────────────────────────┤
  │ settlement_batch.sweep     │ DR merch_payable  97,500                 │
  │                            │ CR bank_payable   97,500                 │
  ├────────────────────────────┼──────────────────────────────────────────┤
  │ settlement_batch.dispatched│ DR bank_payable   97,500                 │
  │                            │ CR float_acct     97,500                 │
  └────────────────────────────┴──────────────────────────────────────────┘

  NET POSITIONS AFTER FULL SETTLEMENT CYCLE:
    float_account:     +100,000 - 100,000 - 97,500 + 97,500 = 0  (net zero)
    merchant_payable:  +97,500  - 97,500                     = 0  (cleared)
    fee_payable:       +2,500                                = +2,500 (Yagye revenue)
    bank_payable:      +97,500  - 97,500                     = 0  (cleared)

  Sum of all accounts = 2,500 = Yagye's earned revenue. ✓

──────────────────────────────────────────────────────────────────────────────

PHASE 5: RECONCILIATION

  ReconciliationWorker (daily):

  1. Verify bank wire landed:
     Compare dispatched settlement_batches against bank statement.
     Mark state = 'reconciled' when confirmed.

  2. Resolve resolution_pending payment_attempts:
     For each attempt in resolution_pending state:
       Query provider API with idempotency_token
       Provider says: succeeded | failed | not_found
       If succeeded: trigger ledger entries (late booking)
       If failed / not_found: mark attempt abandoned after 7-day window

  3. Sweep suspense accounts:
     Any suspense balance older than 30 days with no attribution
     is escalated to ops for manual review.

──────────────────────────────────────────────────────────────────────────────

STATES OF A SETTLEMENT BATCH:

  pending_approval → approved → dispatched → reconciled
                  → rejected  (returned to pending_approval after correction)
```
