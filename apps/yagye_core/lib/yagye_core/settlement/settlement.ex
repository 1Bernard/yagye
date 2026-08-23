defmodule YagyeCore.Settlement do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Pricing.Schemas.FeeRecord
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.{Settlement, SettlementBatch, SettlementItem}

  @open_states ~w[pending processing]

  @doc """
  Creates a pending settlement batch sweeping all unsettled succeeded payments
  for the given merchant, provider, currency, and mode.

  Returns {:error, :no_payments} when there is nothing to settle.
  Returns {:error, :batch_already_open} when a pending/processing batch already
  exists for this (merchant, provider, currency, mode) — protects against double-batching.
  """
  @spec create_batch(binary(), binary(), String.t(), String.t()) ::
          {:ok, SettlementBatch.t()}
          | {:error, :no_payments | :batch_already_open | Ecto.Changeset.t()}
  def create_batch(merchant_id, provider_id, currency, mode) do
    Multi.new()
    |> Multi.run(:guard, fn _repo, _changes ->
      guard_no_open_batch(merchant_id, provider_id, currency, mode)
    end)
    |> Multi.run(:payments, fn _repo, _changes ->
      case do_sweep(merchant_id, provider_id, currency, mode) do
        [] -> {:error, :no_payments}
        payments -> {:ok, payments}
      end
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
        merchant_id: batch.merchant_id,
        provider_id: batch.provider_id,
        currency: batch.currency,
        payment_count: batch.payment_count,
        gross_amount: batch.gross_amount
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{batch: batch}} -> {:ok, batch}
      {:error, :guard, :batch_already_open, _} -> {:error, :batch_already_open}
      {:error, :payments, :no_payments, _} -> {:error, :no_payments}
      {:error, _step, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _} -> {:error, reason}
    end
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
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(s in Settlement,
        where: s.merchant_id == ^merchant_id,
        order_by: [desc: s.inserted_at],
        limit: ^limit
      )

    query =
      if state, do: where(query, [s], s.state == ^state), else: query

    Repo.all(query)
  end

  def transition_settlement(%Settlement{} = settlement, to_state, extra \\ %{}) do
    settlement
    |> Settlement.transition_changeset(to_state, extra)
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

  # ── Batch API ─────────────────────────────────────────────────────────────────

  @doc "Lists batches for a merchant, most recent first."
  def list_batches(merchant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(b in SettlementBatch,
      where: b.merchant_id == ^merchant_id,
      order_by: [desc: b.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
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

  defp load_attempts_for_batch(%SettlementBatch{} = batch) do
    attempt_payment_pairs =
      from(pa in PaymentAttempt,
        join: p in Payment,
        on: p.id == pa.payment_id,
        where: p.settlement_batch_id == ^batch.id and pa.state == "succeeded",
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

    platform_fees = fees["merchant"] || 0
    provider_fees = fees["provider"] || 0
    gross = batch.gross_amount
    expected_net = gross - platform_fees - provider_fees

    {:ok,
     %{
       expected_gross: gross,
       expected_platform_fees: platform_fees,
       expected_provider_fees: provider_fees,
       expected_refunds: 0,
       expected_chargebacks: 0,
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
    items =
      Enum.map(attempt_payment_pairs, fn {attempt, payment} ->
        attrs = %{
          settlement_id: settlement.id,
          source_type: "payment_attempt",
          source_id: attempt.id,
          gross_amount: payment.amount,
          provider_fee: 0,
          platform_fee: 0,
          net_amount: payment.amount,
          currency: payment.currency
        }

        %SettlementItem{}
        |> SettlementItem.create_changeset(attrs)
        |> Repo.insert!(
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:settlement_id, :source_type, :source_id],
          returning: true
        )
      end)

    {:ok, items}
  end

  # Returns payments that succeeded via the given provider and have no batch yet.
  # Conditions on the attempt are in `where` (not `on`) so the filter is applied
  # after the join; using `on` for non-FK conditions produces surprising results
  # in Ecto with inner joins.
  # Joins providers to guard: external_psp payments are settled by the external PSP
  # directly; Yagye must never sweep them into a Yagye settlement batch.
  defp do_sweep(merchant_id, provider_id, currency, mode) do
    from(p in Payment,
      join: pa in PaymentAttempt,
      on: pa.payment_id == p.id,
      join: prov in Provider,
      on: prov.id == pa.provider_id,
      where: prov.kind == "native_rail",
      where: pa.state == "succeeded",
      where: pa.provider_id == ^provider_id,
      where: p.merchant_id == ^merchant_id,
      where: p.currency == ^currency,
      where: p.mode == ^mode,
      where: p.state == "succeeded",
      where: is_nil(p.settlement_batch_id),
      distinct: true,
      select: p
    )
    |> Repo.all()
  end
end
