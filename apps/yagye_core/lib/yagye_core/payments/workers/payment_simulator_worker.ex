defmodule YagyeCore.Payments.Workers.PaymentSimulatorWorker do
  @moduledoc false
  use Oban.Worker, queue: :payments

  alias YagyeCore.Payments

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    Payments.simulate_payment(payment_id)
  end
end
