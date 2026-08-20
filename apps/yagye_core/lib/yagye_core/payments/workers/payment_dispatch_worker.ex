defmodule YagyeCore.Payments.Workers.PaymentDispatchWorker do
  @moduledoc false

  use Oban.Worker, queue: :payments, max_attempts: 3

  alias YagyeCore.Payments
  alias YagyeCore.Payments.ProviderAdapter
  alias YagyeCore.Providers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    with {:ok, payment} <- Payments.dispatch_payment(payment_id),
         {:ok, {provider, credential}} <- Providers.get_provider_for_payment(payment),
         {:ok, attempt} <- Payments.create_attempt(payment, provider.id) do
      result = ProviderAdapter.adapter().charge(payment, attempt, credential)
      Payments.handle_provider_response(payment, attempt, result)
    end
  end
end
