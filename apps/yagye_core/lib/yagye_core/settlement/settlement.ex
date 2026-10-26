defmodule YagyeCore.Settlement do
  @moduledoc false

  import Ecto.Query

  @succeeded "succeeded"

  alias Ecto.Multi
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Pricing.Schemas.FeeRecord
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo

  alias YagyeCore.Disputes.Schemas.Refund

  alias YagyeCore.Settlement.Schemas.{
    MerchantSettlementControls,
    Settlement,
    SettlementBatch,
    SettlementItem
  }

  alias YagyeCore.Settlement.GhanaBusinessDay
  alias YagyeCore.Settlement.Workers.BankDispatchWorker
  alias YagyeCore.Shared.Pagination

  @open_states ~w[pending processing]

  @doc """
  Creates a pending settlement batch sweeping all unsettled succeeded payments
  for the given merchant, provider, currency, and mode.

  Respects per-merchant controls:
  - T+N delay (`settlement_delay_days`): only sweeps payments old enough.
  - Minimum payout (`minimum_payout_pesewas`): skips if gross < minimum.

  Returns {:error, :no_payments} when nothing is eligible yet.
  Returns {:error, :below_minimum} when eligible gross < minimum threshold.
  Returns {:error, :batch_already_open} when a pending/processing batch exists.
  """
  @spec create_batch(binary(), binary(), String.t(), String.t()) ::
          {:ok, SettlementBatch.t()}
          | {:error, :no_payments | :below_minimum | :batch_already_open | Ecto.Changeset.t()}
  def create_batch(merchant_id, provider_id, currency, mode) do
    controls = get_settlement_controls(merchant_id)
    cutoff_dt = controls_cutoff(controls)
    min_payout = controls_min_payout(controls)
    run_batch_multi(merchant_id, provider_id, currency, mode, cutoff_dt, min_payout)
  end

  # ── Settlement records (P12) ─────────────────────────────────────────────────

  @doc """
  Creates a Settlement + SettlementItems from an approved batch.
  The settlement starts in "expected" state. Items are one per payment_attempt.
  Returns {:ok, %{settlement: settlement, items: [item]}} on success.
  """
  def create_settlement_from_batch(%SettlementBatch{} = batch) do
    with {:ok, payment_attempts} <- load_attempts_for_batch(batch),
         {:ok, fee_totals} <- load_fee_totals(batch, payment_attempts) do
      Multi.new()
      |> Multi.insert(:settlement, build_settlement_changeset(batch, fee_totals))
      |> Multi.run(:items, fn _repo, %{settlement: settlement} ->
        insert_settlement_items(settlement, payment_attempts)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{settlement: settlement, items: items}} ->
          {:ok, %{settlement: settlement, items: items}}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  def get_settlement(id) do
    case Repo.get(Settlement, id) do
      nil -> {:error, :not_found}
      s -> {:ok, s}
    end
  end

  def list_settlements(merchant_id, opts \\ []) do
    state = Keyword.get(opts, :state)
    base = from(s in Settlement, where: s.merchant_id == ^merchant_id)
    base = if state, do: where(base, [s], s.state == ^state), else: base
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  def transition_settlement(%Settlement{} = settlement, to_state, extra \\ %{}) do
    settlement
    |> Settlement.transition_changeset(to_state, extra)
    |> Repo.update()
  end

  def initiate_write_off(%Settlement{} = settlement, actor) do
    settlement
    |> Settlement.initiate_write_off_changeset(actor)
    |> Repo.update()
  end

  def approve_write_off(%Settlement{} = settlement, actor) do
    settlement
    |> Settlement.approve_write_off_changeset(actor)
    |> Repo.update()
  end

  @doc """
  Records a provider-reported settlement and moves to "reported" state.
  Triggers the matching step immediately.
  """
  def receive_provider_report(%Settlement{} = settlement, attrs) do
    with {:ok, reported} <-
           transition_settlement(settlement, "reported", %{
             reported_gross: attrs.reported_gross,
             reported_fees: attrs.reported_fees,
             reported_net: attrs.reported_net,
             actual_received: attrs[:actual_received],
             provider_settlement_reference: attrs.provider_settlement_reference,
             value_date: attrs.value_date
           }) do
      run_matching(reported)
    end
  end

  def run_matching(%Settlement{} = settlement) do
    # variance is a DB generated column: reported_net - expected_net
    settlement = Repo.reload!(settlement)

    to_state =
      cond do
        is_nil(settlement.reported_net) -> "expected"
        settlement.variance == 0 -> "matched"
        true -> "mismatched"
      end

    transition_settlement(settlement, to_state)
  end

  # ── Settlement controls ───────────────────────────────────────────────────────

  def get_settlement_controls(merchant_id) do
    Repo.get_by(MerchantSettlementControls, merchant_id: merchant_id)
  end

  def upsert_settlement_controls(merchant_id, attrs) do
    existing = get_settlement_controls(merchant_id) || %MerchantSettlementControls{}

    existing
    |> MerchantSettlementControls.changeset(Map.put(attrs, :merchant_id, merchant_id))
    |> Repo.insert_or_update()
  end

  def approve_batch_dispatch(batch_id, approver_code) do
    batch = Repo.get!(SettlementBatch, batch_id)

    with :ok <- validate_awaiting_approval(batch),
         :ok <- validate_approver(batch.merchant_id, approver_code) do
      Multi.new()
      |> Multi.update(:batch, SettlementBatch.approval_changeset(batch, approver_code))
      |> Multi.insert(:outbox, fn %{batch: b} ->
        Outbox.build_changeset(b, "settlement.batch.dispatch_approved", %{
          settlement_code: b.id,
          merchant_code: b.merchant_id,
          state: "settled",
          dispatch_approved_by: approver_code
        })
      end)
      |> Multi.run(:re_enqueue, fn _repo, %{batch: b} ->
        BankDispatchWorker.new(%{batch_id: b.id}) |> Oban.insert()
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{batch: b}} -> {:ok, b}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  def reject_batch_dispatch(batch_id, rejector_code, reason) do
    batch = Repo.get!(SettlementBatch, batch_id)

    with :ok <- validate_awaiting_approval(batch),
         :ok <- validate_approver(batch.merchant_id, rejector_code) do
      Multi.new()
      |> Multi.update(:batch, SettlementBatch.rejection_changeset(batch, rejector_code, reason))
      |> Multi.insert(:outbox, fn %{batch: b} ->
        Outbox.build_changeset(b, "settlement.batch.dispatch_rejected", %{
          settlement_code: b.id,
          merchant_code: b.merchant_id,
          state: "dispatch_rejected",
          dispatch_rejected_by: rejector_code,
          dispatch_rejection_reason: reason
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{batch: b}} -> {:ok, b}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  defp validate_awaiting_approval(%SettlementBatch{state: "awaiting_approval"}), do: :ok
  defp validate_awaiting_approval(_), do: {:error, :not_awaiting_approval}

  defp validate_approver(merchant_id, user_code) do
    case get_settlement_controls(merchant_id) do
      nil ->
        {:error, :no_controls}

      %{approver_user_codes: codes} ->
        if user_code in codes, do: :ok, else: {:error, :unauthorized_approver}
    end
  end

  # ── Batch API ─────────────────────────────────────────────────────────────────

  @doc "Lists batches for a merchant, most recent first."
  def list_batches(merchant_id, opts \\ []) do
    base = from(b in SettlementBatch, where: b.merchant_id == ^merchant_id)
    # settlement_batches has no public_id; use UUID v7 internal id as cursor
    {:ok, Pagination.paginate(base, :id, opts)}
  end

  @doc "Fetches a batch by id."
  @spec get_batch(binary()) :: SettlementBatch.t() | nil
  def get_batch(id), do: Repo.get(SettlementBatch, id)

  @doc "Transitions a batch to a new state. Returns {:error, :invalid_state} for unknown states."
  @spec transition_batch(SettlementBatch.t(), String.t()) ::
          {:ok, SettlementBatch.t()} | {:error, :invalid_state | Ecto.Changeset.t()}
  def transition_batch(%SettlementBatch{} = batch, to_state) do
    if to_state in SettlementBatch.valid_states() do
      batch |> SettlementBatch.transition_changeset(to_state) |> Repo.update()
    else
      {:error, :invalid_state}
    end
  end

  defp insert_batch(merchant_id, provider_id, currency, mode, payments) do
    oldest = Enum.min_by(payments, & &1.inserted_at, DateTime)
    newest = Enum.max_by(payments, & &1.inserted_at, DateTime)

    attrs = %{
      merchant_id: merchant_id,
      provider_id: provider_id,
      currency: currency,
      mode: mode,
      period_start: oldest.inserted_at,
      # period_end is an exclusive upper bound; must be > period_start
      period_end: DateTime.add(newest.inserted_at, 1, :microsecond),
      payment_count: length(payments),
      gross_amount: Enum.sum(Enum.map(payments, & &1.amount))
    }

    Repo.insert(SettlementBatch.changeset(%SettlementBatch{}, attrs))
  end

  defp stamp_payments(payment_ids, batch_id) do
    {_count, nil} =
      Repo.update_all(
        from(p in Payment, where: p.id in ^payment_ids),
        set: [settlement_batch_id: batch_id]
      )

    {:ok, :stamped}
  end

  defp guard_no_open_batch(merchant_id, provider_id, currency, mode) do
    exists =
      from(b in SettlementBatch,
        where:
          b.merchant_id == ^merchant_id and
            b.provider_id == ^provider_id and
            b.currency == ^currency and
            b.mode == ^mode and
            b.state in ^@open_states
      )
      |> Repo.exists?()

    if exists, do: {:error, :batch_already_open}, else: {:ok, :no_open_batch}
  end

  @doc """
  Computes fee totals for a batch by querying fee_records for all succeeded attempts.
  Called by SettlementProcessorWorker to stamp net_amount/platform_fees on the batch.
  """
  def compute_batch_fee_totals(%SettlementBatch{} = batch) do
    with {:ok, attempt_payment_pairs} <- load_attempts_for_batch(batch) do
      load_fee_totals(batch, attempt_payment_pairs)
    end
  end

  defp load_attempts_for_batch(%SettlementBatch{} = batch) do
    attempt_payment_pairs =
      from(pa in PaymentAttempt,
        join: p in Payment,
        on: p.id == pa.payment_id,
        where: p.settlement_batch_id == ^batch.id and pa.state == @succeeded,
        select: {pa, p}
      )
      |> Repo.all()

    {:ok, attempt_payment_pairs}
  end

  defp load_fee_totals(%SettlementBatch{} = batch, attempt_payment_pairs) do
    attempt_ids = Enum.map(attempt_payment_pairs, fn {attempt, _payment} -> attempt.id end)

    fees =
      from(f in FeeRecord,
        where: f.source_type == "payment_attempt" and f.source_id in ^attempt_ids,
        group_by: f.party,
        select: {f.party, sum(f.amount)}
      )
      |> Repo.all()
      |> Map.new()

    platform_fees = decimal_to_int(fees["platform"])
    provider_fees = decimal_to_int(fees["provider"])
    gross = batch.gross_amount

    controls = get_settlement_controls(batch.merchant_id)
    reserve_bps = (controls && controls.reserve_rate_bps) || 0
    reserved_amount = div(gross * reserve_bps, 10_000)
    expected_refunds = batch_refund_total(batch)

    expected_net = gross - platform_fees - provider_fees - reserved_amount - expected_refunds

    {:ok,
     %{
       expected_gross: gross,
       expected_platform_fees: platform_fees,
       expected_provider_fees: provider_fees,
       expected_refunds: expected_refunds,
       expected_chargebacks: 0,
       reserved_amount: reserved_amount,
       expected_net: expected_net
     }}
  end

  defp build_settlement_changeset(%SettlementBatch{} = batch, fee_totals) do
    Settlement.create_changeset(%Settlement{}, %{
      merchant_id: batch.merchant_id,
      provider_id: batch.provider_id,
      mode: batch.mode,
      currency: batch.currency,
      period_start: batch.period_start,
      period_end: batch.period_end,
      expected_gross: fee_totals.expected_gross,
      expected_provider_fees: fee_totals.expected_provider_fees,
      expected_platform_fees: fee_totals.expected_platform_fees,
      expected_refunds: fee_totals.expected_refunds,
      expected_chargebacks: fee_totals.expected_chargebacks,
      expected_net: fee_totals.expected_net
    })
  end

  defp insert_settlement_items(%Settlement{} = settlement, attempt_payment_pairs) do
    attempt_ids = Enum.map(attempt_payment_pairs, fn {attempt, _} -> attempt.id end)

    fee_map =
      from(f in FeeRecord,
        where:
          f.source_type == "payment_attempt" and f.source_id in ^attempt_ids and
            f.party == "platform",
        select: {f.source_id, f.amount}
      )
      |> Repo.all()
      |> Map.new()

    Enum.reduce_while(attempt_payment_pairs, {:ok, []}, fn {attempt, payment}, {:ok, acc} ->
      platform_fee = Map.get(fee_map, attempt.id, 0)

      attrs = %{
        settlement_id: settlement.id,
        source_type: "payment_attempt",
        source_id: attempt.id,
        gross_amount: payment.amount,
        provider_fee: 0,
        platform_fee: platform_fee,
        net_amount: payment.amount - platform_fee,
        currency: payment.currency
      }

      case %SettlementItem{}
           |> SettlementItem.create_changeset(attrs)
           |> Repo.insert(
             on_conflict: {:replace_all_except, [:id, :inserted_at]},
             conflict_target: [:settlement_id, :source_type, :source_id],
             returning: true
           ) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  # Only apply T+N when controls have an explicit delay (delay_days > 0).
  # 0 = no delay (default for new merchants until ops configures it).
  defp controls_cutoff(%{settlement_delay_days: n}) when is_integer(n) and n > 0,
    do: GhanaBusinessDay.settlement_cutoff_datetime(n)

  defp controls_cutoff(_), do: nil

  defp controls_min_payout(%{minimum_payout_pesewas: min}) when is_integer(min), do: min
  defp controls_min_payout(_), do: 0

  defp run_batch_multi(merchant_id, provider_id, currency, mode, cutoff_dt, min_payout) do
    Multi.new()
    |> Multi.run(:guard, fn _repo, _changes ->
      guard_no_open_batch(merchant_id, provider_id, currency, mode)
    end)
    |> Multi.run(:payments, fn _repo, _changes ->
      sweep_eligible_payments(merchant_id, provider_id, currency, mode, cutoff_dt, min_payout)
    end)
    |> Multi.run(:batch, fn _repo, %{payments: payments} ->
      insert_batch(merchant_id, provider_id, currency, mode, payments)
    end)
    |> Multi.run(:stamp, fn _repo, %{payments: payments, batch: batch} ->
      stamp_payments(Enum.map(payments, & &1.id), batch.id)
    end)
    |> Multi.insert(:outbox, fn %{batch: batch} ->
      Outbox.build_changeset(batch, "settlement.batch.created", %{
        batch_id: batch.id,
        merchant_code: merchant_code(batch.merchant_id),
        provider_code: provider_code(batch.provider_id),
        currency: batch.currency,
        payment_count: batch.payment_count,
        gross_amount: batch.gross_amount
      })
    end)
    |> Repo.transaction()
    |> unwrap_batch_result()
  end

  defp unwrap_batch_result({:ok, %{batch: batch}}), do: {:ok, batch}

  defp unwrap_batch_result({:error, :guard, :batch_already_open, _}),
    do: {:error, :batch_already_open}

  defp unwrap_batch_result({:error, :payments, :no_payments, _}), do: {:error, :no_payments}
  defp unwrap_batch_result({:error, :payments, :below_minimum, _}), do: {:error, :below_minimum}
  defp unwrap_batch_result({:error, _step, %Ecto.Changeset{} = cs, _}), do: {:error, cs}
  defp unwrap_batch_result({:error, _step, reason, _}), do: {:error, reason}

  defp sweep_eligible_payments(merchant_id, provider_id, currency, mode, cutoff_dt, min_payout) do
    payments = do_sweep(merchant_id, provider_id, currency, mode, cutoff_dt)
    gross = Enum.sum(Enum.map(payments, & &1.amount))

    cond do
      payments == [] -> {:error, :no_payments}
      min_payout > 0 and gross < min_payout -> {:error, :below_minimum}
      true -> {:ok, payments}
    end
  end

  # Returns payments that succeeded via the given provider and have no batch yet.
  # Conditions on the attempt are in `where` (not `on`) so the filter is applied
  # after the join; using `on` for non-FK conditions produces surprising results
  # in Ecto with inner joins.
  # Joins providers to guard: external_psp payments are settled by the external PSP
  # directly; Yagye must never sweep them into a Yagye settlement batch.
  defp do_sweep(merchant_id, provider_id, currency, mode, cutoff_dt) do
    base =
      from(p in Payment,
        join: pa in PaymentAttempt,
        on: pa.payment_id == p.id,
        join: prov in Provider,
        on: prov.id == pa.provider_id,
        where: prov.kind == "native_rail",
        where: pa.state == @succeeded,
        where: pa.provider_id == ^provider_id,
        where: p.merchant_id == ^merchant_id,
        where: p.currency == ^currency,
        where: p.mode == ^mode,
        where: p.state == @succeeded,
        where: is_nil(p.settlement_batch_id),
        distinct: true,
        select: p
      )

    base =
      if cutoff_dt do
        where(base, [p], p.inserted_at <= ^cutoff_dt)
      else
        base
      end

    Repo.all(base)
  end

  defp merchant_code(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
      %Merchant{public_id: code} -> code
      nil -> nil
    end
  end

  defp provider_code(provider_id) do
    case Repo.get(Provider, provider_id) do
      %Provider{code: code} -> code
      nil -> nil
    end
  end

  # Sums refunds (requested or succeeded) for all payments in the given batch.
  # These are deducted from expected_net so the reconciliation expectation is accurate.
  defp batch_refund_total(%SettlementBatch{} = batch) do
    result =
      from(r in Refund,
        join: p in Payment,
        on: p.id == r.payment_id,
        where: p.settlement_batch_id == ^batch.id,
        where: r.state in ["requested", "succeeded"],
        select: sum(r.amount)
      )
      |> Repo.one()

    decimal_to_int(result)
  end

  defp decimal_to_int(nil), do: 0
  defp decimal_to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp decimal_to_int(n) when is_integer(n), do: n
end
