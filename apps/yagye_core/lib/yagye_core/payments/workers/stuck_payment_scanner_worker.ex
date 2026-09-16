defmodule YagyeCore.Payments.Workers.StuckPaymentScannerWorker do
  @moduledoc """
  Cron worker that recovers payments orphaned in the `processing` or `requires_action` state.

  **`processing` recovery**: a payment gets stuck here when `PaymentDispatchWorker` crashes
  after `dispatch_payment` sets state to `processing` but before the provider responds. On
  restart Oban retries the job, but if the job is lost (e.g. the node dies hard) this scanner
  re-enqueues `PaymentDispatchWorker`. `dispatch_payment` handles the `processing → processing`
  no-op transition, so re-enqueueing is safe.

  **`requires_action` recovery**: `handle_pending_auth` atomically enqueues `PaymentStatusCheckWorker`
  and `PaymentTimeoutWorker` inside the same transaction as the state transition, so orphaning
  is unlikely. This scan is a defensive backstop — it picks up any payment that somehow still
  sits in `requires_action` well past the maximum prompt timeout (120 s default) and re-fires
  the status check immediately. `PaymentStatusCheckWorker` exits cleanly if the payment has
  already resolved, so this is fully idempotent.

  Runs every 5 minutes.
  """

  use Oban.Worker, queue: :payments, max_attempts: 1

  require Logger

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Payments.Workers.{PaymentDispatchWorker, PaymentStatusCheckWorker}
  alias YagyeCore.Repo

  @stuck_threshold_minutes 5
  @stuck_requires_action_minutes 7
  @batch_size 50

  @impl Oban.Worker
  def perform(_job) do
    recover_processing_payments()
    recover_requires_action_payments()
  end

  defp recover_processing_payments do
    cutoff = DateTime.add(DateTime.utc_now(), -@stuck_threshold_minutes * 60, :second)

    stuck =
      from(p in Payment,
        where: p.state == "processing" and p.inserted_at < ^cutoff,
        select: p.id,
        limit: @batch_size
      )
      |> Repo.all()

    if stuck != [] do
      Logger.info(
        "[StuckPaymentScannerWorker] re-enqueueing #{length(stuck)} stuck processing payments"
      )

      Oban.insert_all(Enum.map(stuck, &PaymentDispatchWorker.new(%{payment_id: &1})))
    end

    :ok
  end

  defp recover_requires_action_payments do
    cutoff = DateTime.add(DateTime.utc_now(), -@stuck_requires_action_minutes * 60, :second)

    stuck =
      from(p in Payment,
        join: a in PaymentAttempt,
        on: a.payment_id == p.id,
        where: p.state == "requires_action" and p.inserted_at < ^cutoff,
        where: a.state == "dispatched",
        distinct: true,
        select: %{payment_id: p.id, attempt_id: a.id},
        limit: @batch_size
      )
      |> Repo.all()

    if stuck != [] do
      Logger.info(
        "[StuckPaymentScannerWorker] recovering #{length(stuck)} stuck requires_action payments"
      )

      jobs =
        Enum.map(stuck, fn %{payment_id: pid, attempt_id: aid} ->
          PaymentStatusCheckWorker.new(%{
            "payment_id" => pid,
            "attempt_id" => aid,
            "poll_number" => 1
          })
        end)

      Oban.insert_all(jobs)
    end

    :ok
  end
end
