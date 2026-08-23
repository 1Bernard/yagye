defmodule YagyeCore.Settlement do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch

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

  # Returns payments that succeeded via the given provider and have no batch yet.
  # Conditions on the attempt are in `where` (not `on`) so the filter is applied
  # after the join; using `on` for non-FK conditions produces surprising results
  # in Ecto with inner joins.
  defp do_sweep(merchant_id, provider_id, currency, mode) do
    from(p in Payment,
      join: pa in PaymentAttempt,
      on: pa.payment_id == p.id,
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
