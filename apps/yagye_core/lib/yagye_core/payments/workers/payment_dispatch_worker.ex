defmodule YagyeCore.Payments.Workers.PaymentDispatchWorker do
  @moduledoc false
  use Oban.Worker, queue: :payments

  alias YagyeCore.Payments
  alias YagyeCore.Payments.Workers.PaymentSimulatorWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    with {:ok, payment} <- Payments.dispatch_payment(payment_id) do
      if payment.mode == "simulation" do
        PaymentSimulatorWorker.new(%{payment_id: payment.id}) |> Oban.insert()
      end

      :ok
    end
  end
end
