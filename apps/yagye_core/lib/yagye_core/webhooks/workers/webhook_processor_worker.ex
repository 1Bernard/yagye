defmodule YagyeCore.Webhooks.Workers.WebhookProcessorWorker do
  @moduledoc false

  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias YagyeCore.Disputes
  alias YagyeCore.Payments
  alias YagyeCore.Payouts
  alias YagyeCore.Payouts.Schemas.Payout
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

  # Paystack Transfer webhooks — handle merchant payout completions.
  # The transfer_code stored as provider_reference on the Payout is the lookup key.

  defp route("paystack", "transfer.success", %{"data" => data}) do
    ref = data["transfer_code"]

    case Repo.get_by(Payout, provider_reference: ref) do
      nil ->
        :ok

      payout ->
        Payouts.mark_paid(payout, ref)
        :ok
    end
  end

  defp route("paystack", "transfer.failed", %{"data" => data}) do
    ref = data["transfer_code"]

    case Repo.get_by(Payout, provider_reference: ref) do
      nil ->
        :ok

      payout ->
        Payouts.mark_returned(payout, "transfer_failed")
        :ok
    end
  end

  defp route("paystack", "transfer.reversed", %{"data" => data}) do
    ref = data["transfer_code"]

    case Repo.get_by(Payout, provider_reference: ref) do
      nil ->
        :ok

      payout ->
        Payouts.mark_returned(payout, "transfer_reversed")
        :ok
    end
  end

  # ── Dispute Retractions ────────────────────────────────────────────────────────
  # Card networks may signal a chargeback withdrawal via charge.dispute.retracted or
  # charge.refunded. Look up the payment by provider reference and retract its
  # open dispute if one exists.

  defp route("flutterwave", "charge.dispute.retracted", %{"data" => data}) do
    id_str = to_string(data["id"])
    retract_dispute_by_provider_ref(id_str)
  end

  defp route("paystack", "charge.dispute.retracted", %{"data" => data}) do
    ref = data["reference"]
    retract_dispute_by_provider_ref(ref)
  end

  # ── Fallthrough ───────────────────────────────────────────────────────────────

  defp route(provider, event_type, _payload),
    do: {:error, {:unknown_event, provider, event_type}}

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp retract_dispute_by_provider_ref(ref) do
    with {:ok, attempt} <- Payments.get_attempt_by_provider_ref(ref),
         {:ok, payment} <- Payments.get_payment_by_id(attempt.payment_id),
         {:ok, dispute} <- Disputes.find_open_dispute_for_payment(payment.id) do
      case Disputes.retract_dispute(dispute) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found} -> :ok
    end
  end

  defp flutterwave_result(%{"status" => "successful", "flw_ref" => flw_ref}, id_str) do
    {:ok, %{provider_reference: id_str, auth_code: flw_ref}}
  end

  defp flutterwave_result(%{"status" => status}, _id_str) do
    {:error,
     %{error_class: :definite_failure, response_code: "flw_#{status}", response_message: nil}}
  end
end
