defmodule YagyeCore.Settlement do
  @moduledoc false

  import Ecto.Query

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
    result =
      Repo.transaction(fn ->
        with :ok <- guard_no_open_batch(merchant_id, provider_id, currency, mode),
             [_ | _] = payments <- do_sweep(merchant_id, provider_id, currency, mode),
             {:ok, batch} <- insert_batch(merchant_id, provider_id, currency, mode, payments),
             :ok <- stamp_payments(Enum.map(payments, & &1.id), batch.id),
             {:ok, _} <- emit_created_event(batch) do
          batch
        else
          :error -> Repo.rollback(:batch_already_open)
          [] -> Repo.rollback(:no_payments)
          {:error, cs} when is_struct(cs, Ecto.Changeset) -> Repo.rollback({:changeset, cs})
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, batch} -> {:ok, batch}
      {:error, {:changeset, cs}} -> {:error, cs}
      {:error, reason} -> {:error, reason}
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

  defp emit_created_event(%SettlementBatch{} = batch) do
    Outbox.emit(batch, "settlement.batch.created", %{
      batch_id: batch.id,
      merchant_id: batch.merchant_id,
      provider_id: batch.provider_id,
      currency: batch.currency,
      payment_count: batch.payment_count,
      gross_amount: batch.gross_amount
    })
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

  # Stamps settlement_batch_id on all swept payments in one bulk UPDATE.
  defp stamp_payments(payment_ids, batch_id) do
    {_count, nil} =
      Repo.update_all(
        from(p in Payment, where: p.id in ^payment_ids),
        set: [settlement_batch_id: batch_id]
      )

    :ok
  end

  # Returns :ok when no pending/processing batch exists; :error otherwise.
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

    if exists, do: :error, else: :ok
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
