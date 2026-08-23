defmodule YagyeCore.Webhooks.Workers.WebhookProcessorWorker do
  @moduledoc false

  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias YagyeCore.Payments
  alias YagyeCore.Repo
  alias YagyeCore.Webhooks
  alias YagyeCore.Webhooks.Schemas.WebhookEvent

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => id}}) do
    webhook = Repo.get!(WebhookEvent, id)
    payload = Jason.decode!(webhook.raw_body)

    case route(webhook.event_type, payload) do
      :ok ->
        Webhooks.mark_processed(webhook)
        :ok

      {:error, reason} ->
        Webhooks.mark_failed(webhook, inspect(reason))
        {:error, reason}
    end
  end

  defp route("charge.succeeded", %{"charge_ref" => charge_ref} = payload) do
    with {:ok, attempt} <- Payments.get_attempt_by_provider_ref(charge_ref),
         {:ok, payment} <- Payments.get_payment_by_id(attempt.payment_id) do
      result = {:ok, %{provider_reference: charge_ref, auth_code: payload["auth_code"]}}
      Payments.handle_provider_response(payment, attempt, result)
      :ok
    end
  end

  defp route("charge.failed", %{"charge_ref" => charge_ref} = payload) do
    with {:ok, attempt} <- Payments.get_attempt_by_provider_ref(charge_ref),
         {:ok, payment} <- Payments.get_payment_by_id(attempt.payment_id) do
      result =
        {:error,
         %{
           error_class: :definite_failure,
           response_code: payload["decline_code"] || "webhook_declined",
           response_message: nil
         }}

      Payments.handle_provider_response(payment, attempt, result)
      :ok
    end
  end

  defp route(event_type, _payload), do: {:error, {:unknown_event_type, event_type}}
end
