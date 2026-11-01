defmodule YagyeCore.Splits.Workers.SplitDistributorWorker do
  @moduledoc false

  use Oban.Worker, queue: :payments, max_attempts: 3

  require Logger

  alias YagyeCore.Ledger
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo
  alias YagyeCore.Splits
  alias YagyeCore.Splits.Schemas.SplitRecord

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    payment = Repo.get!(Payment, payment_id)

    case Splits.split_rule_for(payment) do
      {:ok, :no_split} ->
        :ok

      {:ok, rule} ->
        distribute(payment, rule)

      {:error, reason} ->
        Logger.error("split_distributor: rule lookup failed",
          payment_id: payment_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp distribute(payment, rule) do
    with {:ok, records} <- Splits.create_records_for_payment(payment, rule) do
      Enum.reduce_while(records, :ok, &settle_record(payment, &1, &2))
    end
  end

  defp settle_record(payment, record, _acc) do
    case post_and_settle(payment, record) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp post_and_settle(%Payment{} = payment, %SplitRecord{} = record) do
    with {:ok, _entry} <- Ledger.post_split_distribution(payment, record.id, record.amount),
         {:ok, _} <- Splits.mark_settled(record.id) do
      :ok
    else
      {:error, reason} ->
        Logger.error("split_distributor: leg failed",
          payment_id: payment.id,
          split_record_id: record.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
