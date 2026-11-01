defmodule YagyeCore.Escrow.Workers.DisputeWindowExpiryWorker do
  @moduledoc false

  use Oban.Worker, queue: :payments, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.Escrow
  alias YagyeCore.Escrow.Schemas.EscrowHold
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"hold_id" => hold_id}}) do
    hold = Repo.get(EscrowHold, hold_id)

    if hold && hold.state == "held" &&
         DateTime.compare(hold.dispute_window_ends_at, DateTime.utc_now()) != :gt do
      attempt = latest_succeeded_attempt(hold.payment_id)

      case Escrow.auto_release(hold_id, attempt) do
        {:ok, _} ->
          :ok

        {:error, :not_held} ->
          :ok

        {:error, reason} ->
          Logger.error("dispute window expiry release failed",
            hold_id: hold_id,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    else
      :ok
    end
  end

  defp latest_succeeded_attempt(payment_id) do
    PaymentAttempt
    |> where([a], a.payment_id == ^payment_id and a.state == "succeeded")
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one!()
  end
end
