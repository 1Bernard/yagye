defmodule YagyeCore.Payments.Workers.StuckPaymentScannerWorker do
  @moduledoc """
  Cron worker that recovers payments orphaned in the `processing` state.

  A payment gets stuck in `processing` when `PaymentDispatchWorker` crashes after
  calling `dispatch_payment` (which sets state to `processing`) but before the
  provider responds. On restart Oban retries the job, but if the job is lost (e.g.
  the node dies hard) this scanner is the backstop.

  Runs every 5 minutes. For each `processing` payment older than 5 minutes it
  re-enqueues `PaymentDispatchWorker`. `dispatch_payment` handles the
  `processing → processing` no-op transition, so re-enqueueing is safe.
  """

  use Oban.Worker, queue: :payments, max_attempts: 1

  require Logger

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Workers.PaymentDispatchWorker
  alias YagyeCore.Repo

  @stuck_threshold_minutes 5
  @batch_size 50

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@stuck_threshold_minutes * 60, :second)

    stuck =
      from(p in Payment,
        where: p.state == "processing" and p.inserted_at < ^cutoff,
        select: p.id,
        limit: @batch_size
      )
      |> Repo.all()

    if stuck == [] do
      :ok
    else
      Logger.info("[StuckPaymentScannerWorker] re-enqueueing #{length(stuck)} stuck payments")

      jobs =
        Enum.map(stuck, fn payment_id ->
          PaymentDispatchWorker.new(%{payment_id: payment_id})
        end)

      Oban.insert_all(jobs)
      :ok
    end
  end
end
