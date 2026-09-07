defmodule YagyeCore.Payments.Workers.PaymentTimeoutWorker do
  @moduledoc """
  Hard timeout for MoMo payments stuck in `requires_action`.

  Scheduled by `handle_pending_auth` with `schedule_in: prompt_timeout_seconds`.
  If the payment is still in `requires_action` when this fires (i.e. the customer
  never responded and no webhook arrived), the payment is marked `failed`.

  If `PaymentStatusCheckWorker` or an inbound webhook already resolved the payment,
  this is a no-op.
  """

  use Oban.Worker, queue: :payments, max_attempts: 3

  require Logger

  alias YagyeCore.Payments
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id, "attempt_id" => attempt_id}}) do
    with {:ok, payment} <- Payments.get_payment_by_id(payment_id),
         :still_pending <- check_state(payment) do
      attempt = Repo.get(PaymentAttempt, attempt_id)
      Payments.handle_prompt_timeout(payment, attempt)
    else
      :already_resolved ->
        :ok

      {:error, :not_found} ->
        Logger.warning("[PaymentTimeoutWorker] payment not found", payment_id: payment_id)
        :ok
    end
  end

  defp check_state(%Payment{state: "requires_action"}), do: :still_pending
  defp check_state(_payment), do: :already_resolved
end
