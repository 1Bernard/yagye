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

    # Idempotency guard: a prior attempt already completed successfully.
    if webhook.state == "processed" do
      :ok
    else
      payload = Jason.decode!(webhook.raw_body)

      case route(webhook.provider_code, webhook.event_type, payload) do
        :ok ->
          Webhooks.mark_processed(webhook)
          :ok

        {:error, reason} ->
          Webhooks.mark_failed(webhook, inspect(reason))
          {:error, reason}
      end
    end
  end

  # ── Simulator ────────────────────────────────────────────────────────────────

  defp route("simulator", "charge.succeeded", %{"charge_ref" => charge_ref} = payload) do
    with {:ok, attempt} <- Payments.get_attempt_by_provider_ref(charge_ref),
         {:ok, payment} <- Payments.get_payment_by_id(attempt.payment_id) do
      result = {:ok, %{provider_reference: charge_ref, auth_code: payload["auth_code"]}}
      Payments.handle_provider_response(payment, attempt, result)
      :ok
    end
  end

  defp route("simulator", "charge.failed", %{"charge_ref" => charge_ref} = payload) do
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

  # ── Flutterwave ──────────────────────────────────────────────────────────────
  # Flutterwave uses the numeric transaction id (data.id) as the canonical
  # identifier. The provider_reference stored on the attempt is to_string(data.id).

  defp route("flutterwave", "charge.completed", %{"data" => data}) do
    id_str = to_string(data["id"])

    with {:ok, attempt} <- Payments.get_attempt_by_provider_ref(id_str),
         {:ok, payment} <- Payments.get_payment_by_id(attempt.payment_id) do
      result = flutterwave_result(data, id_str)
      Payments.handle_provider_response(payment, attempt, result)
      :ok
    end
  end

  # ── Paystack ─────────────────────────────────────────────────────────────────
  # Paystack uses the transaction reference string (which Yagye sets to the
  # idempotency_token) as the canonical identifier.

  defp route("paystack", "charge.success", %{"data" => data}) do
    ref = data["reference"]

    with {:ok, attempt} <- Payments.get_attempt_by_provider_ref(ref),
         {:ok, payment} <- Payments.get_payment_by_id(attempt.payment_id) do
      result = {:ok, %{provider_reference: ref, auth_code: nil}}
      Payments.handle_provider_response(payment, attempt, result)
      :ok
    end
  end

  defp route("paystack", "charge.failed", %{"data" => data}) do
    ref = data["reference"]

    with {:ok, attempt} <- Payments.get_attempt_by_provider_ref(ref),
         {:ok, payment} <- Payments.get_payment_by_id(attempt.payment_id) do
      result =
        {:error,
         %{
           error_class: :definite_failure,
           response_code: "ps_failed",
           response_message: data["gateway_response"]
         }}

      Payments.handle_provider_response(payment, attempt, result)
      :ok
    end
  end

  # ── Fallthrough ───────────────────────────────────────────────────────────────

  defp route(provider, event_type, _payload),
    do: {:error, {:unknown_event, provider, event_type}}

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp flutterwave_result(%{"status" => "successful", "flw_ref" => flw_ref}, id_str) do
    {:ok, %{provider_reference: id_str, auth_code: flw_ref}}
  end

  defp flutterwave_result(%{"status" => status}, _id_str) do
    {:error,
     %{error_class: :definite_failure, response_code: "flw_#{status}", response_message: nil}}
  end
end
