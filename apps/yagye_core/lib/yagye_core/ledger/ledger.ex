defmodule YagyeCore.Ledger do
  @moduledoc false

  require OpenTelemetry.Tracer

  import Ecto.Query

  alias YagyeCore.Disputes.Schemas.Refund
  alias YagyeCore.Ledger.Schemas.{Account, Balance, Entry, Posting}
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Payouts.Schemas.Payout
  alias YagyeCore.Pricing.Schemas.FeeRecord
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Reserves.Schemas.ReserveHold
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  # ── Public API ───────────────────────────────────────────────────────────────

  # Posts the "payment_settled" journal entry when a payment succeeds.
  # Must be called within the handle_provider_response transaction so the
  # ledger write and the payment state change are atomic.
  #
  # Accounts created on demand (idempotent via ON CONFLICT DO NOTHING).
  # Balance updated via INSERT ... ON CONFLICT DO UPDATE — atomic, no race.
  #
  # Debit  : settlement_pending — we are owed funds from the provider (asset ↑)
  # Credit : merchant_payable   — we owe the merchant net funds (liability ↑)
  #
  # For external_psp providers, Yagye never holds the settlement float — the
  # external PSP settles directly to the merchant. Skip the settlement entry;
  # the orchestration fee is captured separately via post_fee_deduction.
  def post_payment_settled(%Payment{} = payment, %PaymentAttempt{} = attempt) do
    provider = Repo.get!(Provider, attempt.provider_id)

    if provider.kind == "external_psp" do
      {:ok, :no_settlement}
    else
      do_post_payment_settled(payment, attempt)
    end
  end

  defp do_post_payment_settled(%Payment{} = payment, %PaymentAttempt{} = attempt) do
    OpenTelemetry.Tracer.with_span "ledger.post_settlement" do
      with {:ok, settlement_account} <-
             get_or_create_account(%{
               account_type: "settlement_pending",
               normal_balance: "debit",
               scope_type: "provider",
               scope_id: attempt.provider_id,
               currency: payment.currency,
               mode: payment.mode,
               allows_negative: false
             }),
           {:ok, merchant_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: payment.merchant_id,
               currency: payment.currency,
               mode: payment.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_entry(payment),
           {:ok, debit} <-
             insert_posting(
               entry,
               settlement_account,
               "debit",
               payment.amount,
               payment.merchant_id
             ),
           {:ok, credit} <-
             insert_posting(
               entry,
               merchant_account,
               "credit",
               payment.amount,
               payment.merchant_id
             ) do
        apply_balance(settlement_account.id, payment.amount, :debit, debit.id)
        apply_balance(merchant_account.id, payment.amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  @doc """
  Posts the "refund_issued" reversal entry when a refund is processed.

  Must be called within the Disputes.create_refund transaction.

  Reverses the original payment_settled entry:
    Debit  : merchant_payable   — reduce what we owe the merchant (liability ↓)
    Credit : settlement_pending — reduce what we're owed from provider (asset ↓)
  """
  def post_refund(%Payment{} = payment, %PaymentAttempt{} = attempt, %Refund{} = refund) do
    OpenTelemetry.Tracer.with_span "ledger.post_refund" do
      with {:ok, merchant_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: payment.merchant_id,
               currency: payment.currency,
               mode: payment.mode,
               allows_negative: false
             }),
           {:ok, settlement_account} <-
             get_or_create_account(%{
               account_type: "settlement_pending",
               normal_balance: "debit",
               scope_type: "provider",
               scope_id: attempt.provider_id,
               currency: payment.currency,
               mode: payment.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_refund_entry(payment, refund),
           {:ok, debit} <-
             insert_posting(entry, merchant_account, "debit", refund.amount, payment.merchant_id),
           {:ok, credit} <-
             insert_posting(
               entry,
               settlement_account,
               "credit",
               refund.amount,
               payment.merchant_id
             ) do
        apply_balance(merchant_account.id, refund.amount, :debit, debit.id)
        apply_balance(settlement_account.id, refund.amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  @doc """
  Posts the "batch_approved" journal entry when a settlement batch is approved for disbursement.

  Must be called within the SettlementProcessorWorker transaction so the ledger
  write and the batch state transition are atomic.

  Debit  : merchant_payable   — reduce the merchant's outstanding payable (liability ↓)
  Credit : settlement_approved — funds committed for wire transfer (liability ↑)

  Once the wire is sent (Step 5 completion), a separate entry will debit
  settlement_approved and credit settlement_pending to close the loop.
  """
  def post_batch_approved(%SettlementBatch{} = batch) do
    OpenTelemetry.Tracer.with_span "ledger.post_batch_approved" do
      with {:ok, payable_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: batch.merchant_id,
               currency: batch.currency,
               mode: batch.mode,
               allows_negative: false
             }),
           {:ok, approved_account} <-
             get_or_create_account(%{
               account_type: "settlement_approved",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: batch.merchant_id,
               currency: batch.currency,
               mode: batch.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_batch_entry(batch),
           {:ok, debit} <-
             insert_posting(
               entry,
               payable_account,
               "debit",
               batch.gross_amount,
               batch.merchant_id
             ),
           {:ok, credit} <-
             insert_posting(
               entry,
               approved_account,
               "credit",
               batch.gross_amount,
               batch.merchant_id
             ) do
        apply_balance(payable_account.id, batch.gross_amount, :debit, debit.id)
        apply_balance(approved_account.id, batch.gross_amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  def get_balance(account_id) do
    case Repo.get(Balance, account_id) do
      nil -> {:ok, 0}
      bal -> {:ok, bal.balance}
    end
  end

  def get_account(code) do
    case Repo.get_by(Account, code: code) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  @doc """
  Posts a reconciliation correction entry.

  `direction` in opts:
    - `"credit_merchant"` — provider owes merchant more (debit suspense, credit payable)
    - `"debit_merchant"` — merchant was overpaid (debit payable, credit suspense)
  """
  def post_correction(break, opts) do
    alias YagyeCore.Reconciliation.Schemas.ReconciliationBreak

    %ReconciliationBreak{} = break
    amount = opts[:amount] || opts["amount"]
    direction = opts[:direction] || opts["direction"] || "credit_merchant"

    OpenTelemetry.Tracer.with_span "ledger.post_correction" do
      with {:ok, suspense_account} <-
             get_or_create_account(%{
               account_type: "reconciliation_suspense",
               normal_balance: "debit",
               scope_type: "merchant",
               scope_id: break.merchant_id,
               currency: break.currency,
               mode: break.mode,
               allows_negative: true
             }),
           {:ok, payable_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: break.merchant_id,
               currency: break.currency,
               mode: break.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_correction_entry(break, amount) do
        {debit_account, credit_account} =
          if direction == "credit_merchant",
            do: {suspense_account, payable_account},
            else: {payable_account, suspense_account}

        with {:ok, debit} <-
               insert_posting(entry, debit_account, "debit", amount, break.merchant_id),
             {:ok, credit} <-
               insert_posting(entry, credit_account, "credit", amount, break.merchant_id) do
          apply_balance(debit_account.id, amount, :debit, debit.id)
          apply_balance(credit_account.id, amount, :credit, credit.id)
          {:ok, entry}
        end
      end
    end
  end

  @doc """
  Posts the "fee_deduction" journal entry when a platform fee is computed.

  Must be called in the same transaction as post_payment_settled so the fee
  deduction is atomic with the payment settlement.

  Debit  : merchant_payable    — reduce what we owe the merchant by the fee
  Credit : processing_revenue  — Yagye earns the processing fee (platform-scoped)
  """
  def post_fee_deduction(%Payment{} = payment, %FeeRecord{} = fee_record) do
    OpenTelemetry.Tracer.with_span "ledger.post_fee_deduction" do
      with {:ok, payable_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: payment.merchant_id,
               currency: payment.currency,
               mode: payment.mode,
               allows_negative: false
             }),
           {:ok, revenue_account} <-
             get_or_create_account(%{
               account_type: "processing_revenue",
               normal_balance: "credit",
               scope_type: "platform",
               scope_id: nil,
               currency: fee_record.currency,
               mode: payment.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_fee_entry(payment, fee_record),
           {:ok, debit} <-
             insert_posting(
               entry,
               payable_account,
               "debit",
               fee_record.amount,
               payment.merchant_id
             ),
           {:ok, credit} <-
             insert_posting(
               entry,
               revenue_account,
               "credit",
               fee_record.amount,
               payment.merchant_id
             ) do
        apply_balance(payable_account.id, fee_record.amount, :debit, debit.id)
        apply_balance(revenue_account.id, fee_record.amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  @doc """
  Posts the "payout_committed" entry when a payout is being submitted to a provider.

  Debit  : merchant_payable  — reduce the outstanding merchant payable (liability ↓)
  Credit : payout_transit    — funds in-flight to merchant (liability ↑ until confirmed)
  """
  def post_payout_committed(%Payout{} = payout) do
    OpenTelemetry.Tracer.with_span "ledger.post_payout_committed" do
      with {:ok, payable_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: payout.merchant_id,
               currency: payout.currency,
               mode: payout.mode,
               allows_negative: false
             }),
           {:ok, transit_account} <-
             get_or_create_account(%{
               account_type: "payout_transit",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: payout.merchant_id,
               currency: payout.currency,
               mode: payout.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_payout_committed_entry(payout),
           {:ok, debit} <-
             insert_posting(entry, payable_account, "debit", payout.amount, payout.merchant_id),
           {:ok, credit} <-
             insert_posting(entry, transit_account, "credit", payout.amount, payout.merchant_id) do
        apply_balance(payable_account.id, payout.amount, :debit, debit.id)
        apply_balance(transit_account.id, payout.amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  @doc """
  Posts the "reserve_held" entry when a reserve hold is created on payment success.

  Debit  : merchant_payable  — reduce what we immediately owe the merchant
  Credit : merchant_reserve  — funds held under reserve policy
  """
  def post_reserve_hold(%Payment{} = payment, %ReserveHold{} = hold) do
    OpenTelemetry.Tracer.with_span "ledger.post_reserve_hold" do
      with {:ok, payable_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: payment.merchant_id,
               currency: hold.currency,
               mode: hold.mode,
               allows_negative: false
             }),
           {:ok, reserve_account} <-
             get_or_create_account(%{
               account_type: "merchant_reserve",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: payment.merchant_id,
               currency: hold.currency,
               mode: hold.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_reserve_hold_entry(hold),
           {:ok, debit} <-
             insert_posting(entry, payable_account, "debit", hold.amount, payment.merchant_id),
           {:ok, credit} <-
             insert_posting(entry, reserve_account, "credit", hold.amount, payment.merchant_id) do
        apply_balance(payable_account.id, hold.amount, :debit, debit.id)
        apply_balance(reserve_account.id, hold.amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  @doc """
  Posts the "reserve_released" entry when a hold's release_at date is reached.

  Debit  : merchant_reserve  — reduce the reserve balance
  Credit : merchant_payable  — restore owed funds to merchant
  """
  def post_reserve_release(%ReserveHold{} = hold) do
    OpenTelemetry.Tracer.with_span "ledger.post_reserve_release" do
      with {:ok, reserve_account} <-
             get_or_create_account(%{
               account_type: "merchant_reserve",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: hold.merchant_id,
               currency: hold.currency,
               mode: hold.mode,
               allows_negative: false
             }),
           {:ok, payable_account} <-
             get_or_create_account(%{
               account_type: "merchant_payable",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: hold.merchant_id,
               currency: hold.currency,
               mode: hold.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_reserve_release_entry(hold),
           {:ok, debit} <-
             insert_posting(entry, reserve_account, "debit", hold.amount, hold.merchant_id),
           {:ok, credit} <-
             insert_posting(entry, payable_account, "credit", hold.amount, hold.merchant_id) do
        apply_balance(reserve_account.id, hold.amount, :debit, debit.id)
        apply_balance(payable_account.id, hold.amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  @doc """
  Posts the "reserve_drawn" entry when a hold is consumed to cover a chargeback.

  Debit  : merchant_reserve    — reduce the reserve balance
  Credit : reserve_recovery    — Yagye platform recovers funds (platform-scoped)
  """
  def post_reserve_draw(%ReserveHold{} = hold) do
    OpenTelemetry.Tracer.with_span "ledger.post_reserve_draw" do
      with {:ok, reserve_account} <-
             get_or_create_account(%{
               account_type: "merchant_reserve",
               normal_balance: "credit",
               scope_type: "merchant",
               scope_id: hold.merchant_id,
               currency: hold.currency,
               mode: hold.mode,
               allows_negative: false
             }),
           {:ok, recovery_account} <-
             get_or_create_account(%{
               account_type: "reserve_recovery",
               normal_balance: "credit",
               scope_type: "platform",
               scope_id: nil,
               currency: hold.currency,
               mode: hold.mode,
               allows_negative: false
             }),
           {:ok, entry} <- insert_reserve_draw_entry(hold),
           {:ok, debit} <-
             insert_posting(entry, reserve_account, "debit", hold.amount, hold.merchant_id),
           {:ok, credit} <-
             insert_posting(entry, recovery_account, "credit", hold.amount, hold.merchant_id) do
        apply_balance(reserve_account.id, hold.amount, :debit, debit.id)
        apply_balance(recovery_account.id, hold.amount, :credit, credit.id)
        {:ok, entry}
      end
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp get_or_create_account(attrs) do
    code = build_account_code(attrs)
    attrs = Map.put(attrs, :code, code)

    # Uniq.UUID generates IDs client-side, so the returned struct always has a
    # non-nil id even when ON CONFLICT DO NOTHING skips the insert. We can't use
    # {:ok, %Account{id: nil}} to detect conflicts — always fetch from DB instead.
    case Repo.insert(Account.changeset(%Account{}, attrs),
           on_conflict: :nothing,
           conflict_target: :code
         ) do
      {:ok, _} ->
        {:ok, Repo.get_by!(Account, code: code)}

      {:error, _} = err ->
        err
    end
  end

  defp insert_refund_entry(%Payment{} = payment, %Refund{} = refund) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: payment.mode,
      currency: payment.currency,
      entry_type: "refund_issued",
      source_type: "refund",
      source_id: refund.id,
      description: "Refund issued: #{refund.public_id} for #{payment.public_id}",
      correlation_id: payment.public_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "refund",
           source_id: refund.id,
           entry_type: "refund_issued"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_entry(%Payment{} = payment) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: payment.mode,
      currency: payment.currency,
      entry_type: "payment_settled",
      source_type: "payment",
      source_id: payment.id,
      description: "Payment settled: #{payment.public_id}",
      correlation_id: payment.public_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        # Fetch from DB — Uniq.UUID generates IDs client-side so id: nil detection
        # is unreliable when ON CONFLICT DO NOTHING skips the insert.
        {:ok,
         Repo.get_by!(Entry,
           source_type: "payment",
           source_id: payment.id,
           entry_type: "payment_settled"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_batch_entry(%SettlementBatch{} = batch) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: batch.mode,
      currency: batch.currency,
      entry_type: "batch_approved",
      source_type: "settlement_batch",
      source_id: batch.id,
      description: "Batch approved for settlement: #{batch.id}",
      correlation_id: batch.id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "settlement_batch",
           source_id: batch.id,
           entry_type: "batch_approved"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_fee_entry(%Payment{} = payment, %FeeRecord{} = fee_record) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: payment.mode,
      currency: fee_record.currency,
      entry_type: "fee_deduction",
      source_type: "fee_record",
      source_id: fee_record.id,
      description:
        "Fee deduction: #{fee_record.amount} #{fee_record.currency} for #{payment.public_id}",
      correlation_id: payment.public_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "fee_record",
           source_id: fee_record.id,
           entry_type: "fee_deduction"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_correction_entry(break, _amount) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: break.mode,
      currency: break.currency,
      entry_type: "reconciliation_correction",
      source_type: "reconciliation_break",
      source_id: break.id,
      description: "Reconciliation correction: #{break.public_id}",
      correlation_id: break.public_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "reconciliation_break",
           source_id: break.id,
           entry_type: "reconciliation_correction"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_payout_committed_entry(%Payout{} = payout) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: payout.mode,
      currency: payout.currency,
      entry_type: "payout_committed",
      source_type: "payout",
      source_id: payout.id,
      description: "Payout committed: #{payout.public_id}",
      correlation_id: payout.public_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "payout",
           source_id: payout.id,
           entry_type: "payout_committed"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_reserve_hold_entry(%ReserveHold{} = hold) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: hold.mode,
      currency: hold.currency,
      entry_type: "reserve_held",
      source_type: "reserve_hold",
      source_id: hold.id,
      description: "Reserve held for payment #{hold.payment_id}",
      correlation_id: hold.payment_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "reserve_hold",
           source_id: hold.id,
           entry_type: "reserve_held"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_reserve_release_entry(%ReserveHold{} = hold) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: hold.mode,
      currency: hold.currency,
      entry_type: "reserve_released",
      source_type: "reserve_hold",
      source_id: hold.id,
      description: "Reserve released for payment #{hold.payment_id}",
      correlation_id: hold.payment_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "reserve_hold",
           source_id: hold.id,
           entry_type: "reserve_released"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_reserve_draw_entry(%ReserveHold{} = hold) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: hold.mode,
      currency: hold.currency,
      entry_type: "reserve_drawn",
      source_type: "reserve_hold",
      source_id: hold.id,
      description: "Reserve drawn for chargeback on payment #{hold.payment_id}",
      correlation_id: hold.payment_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Entry,
           source_type: "reserve_hold",
           source_id: hold.id,
           entry_type: "reserve_drawn"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_posting(%Entry{} = entry, %Account{} = account, direction, amount, merchant_id) do
    Posting.changeset(%Posting{}, %{
      entry_id: entry.id,
      account_id: account.id,
      direction: direction,
      amount: amount,
      currency: account.currency,
      merchant_id: merchant_id
    })
    |> Repo.insert()
  end

  # SELECT FOR UPDATE locks the balance row before applying the delta.
  # This prevents concurrent payments for the same account from producing incorrect balances.
  # If no balance row exists yet, INSERT the first one.
  defp apply_balance(account_id, amount, direction, posting_id) do
    delta = if direction == :debit, do: amount, else: -amount
    now = DateTime.utc_now()

    existing =
      from(b in "ledger_balances",
        where: b.account_id == type(^account_id, :binary_id),
        lock: "FOR UPDATE",
        select: b.balance
      )
      |> Repo.one()

    case existing do
      nil ->
        Repo.insert_all("ledger_balances", [
          %{
            account_id: Ecto.UUID.dump!(account_id),
            balance: delta,
            last_posting_id: posting_id,
            updated_at: now
          }
        ])

      _ ->
        Repo.update_all(
          from(b in "ledger_balances",
            where: b.account_id == type(^account_id, :binary_id)
          ),
          inc: [balance: delta],
          set: [last_posting_id: posting_id, updated_at: now]
        )
    end
  end

  defp build_account_code(%{account_type: type, scope_id: nil, currency: currency, mode: mode}) do
    "#{type}:platform:#{currency}:#{mode}"
  end

  defp build_account_code(%{
         account_type: type,
         scope_id: scope_id,
         currency: currency,
         mode: mode
       }) do
    "#{type}:#{scope_id}:#{currency}:#{mode}"
  end
end
