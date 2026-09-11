defmodule YagyeCore.Payments.Adapters.FlutterwaveAdapter do
  @moduledoc """
  Payment adapter for Flutterwave (external PSP, Model B).

  Handles mobile money payments in Ghana (GHS) via Flutterwave's MoMo API.
  Card support is deferred — Flutterwave card charges require 3DS redirect flows
  which need hosted checkout integration.

  ## Amount handling
  Flutterwave accepts amounts in the currency's MAJOR unit (cedis for GHS),
  not minor units (pesewas). Since Yagye stores all amounts as minor-unit
  integers, this adapter divides by 100 before sending to Flutterwave.

  ## Mobile money flow (async)
  1. POST /v3/charges?type=mobile_money_gh → Flutterwave sends USSD push to customer
  2. Returns {:pending, ...} — payment is in requires_action state
  3. Customer approves on phone → Flutterwave sends charge.completed webhook
  4. Webhook processor calls handle_provider_response to complete the payment

  ## Credentials (stored in provider_credentials.encrypted_payload)
  - "secret_key" — Flutterwave secret key (FLWSECK_TEST-... or FLWSECK-...)
  - "public_key" — Flutterwave public key (optional, not needed for server calls)
  - "webhook_hash" — the static hash set in Flutterwave Dashboard → Webhooks

  ## Network codes
  Ghana MoMo networks in Flutterwave:
  - "MTN"   → MTN Mobile Money
  - "VDF"   → Vodafone Cash
  - "ATL"   → AirtelTigo Money
  """

  @behaviour YagyeCore.Payments.ProviderAdapter

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  # Maps Yagye's internal network names to Flutterwave's codes.
  @network_map %{
    "MTN" => "MTN",
    "Vodafone" => "VDF",
    "AirtelTigo" => "ATL",
    "mtn" => "MTN",
    "vodafone" => "VDF",
    "airteltigo" => "ATL"
  }

  @impl true
  def charge(%Payment{method: "mobile_money"} = payment, %PaymentAttempt{} = attempt, credential) do
    network = get_in(payment.metadata, ["network"]) || "MTN"
    msisdn = get_in(payment.metadata, ["msisdn"]) || ""
    email = get_in(payment.metadata, ["email"]) || "payments@yagye.com"

    body = %{
      tx_ref: attempt.idempotency_token,
      amount: to_major_units(payment.amount, payment.currency),
      currency: payment.currency,
      network: Map.get(@network_map, network, network),
      email: email,
      phone_number: msisdn,
      fullname: get_in(payment.metadata, ["account_name"]) || "Customer"
    }

    Req.post(url("/charges", credential, type: "mobile_money_gh"),
      json: body,
      headers: auth_headers(credential),
      receive_timeout: 15_000
    )
    |> translate_charge_http_response()
  end

  def charge(%Payment{} = _payment, %PaymentAttempt{} = _attempt, _credential) do
    # Card and bank transfer via Flutterwave require redirect / hosted flows.
    # These are not supported in the server-side adapter path.
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "method_not_supported",
       response_message: "Use hosted checkout for Flutterwave card/bank payments"
     }}
  end

  @impl true
  def query_charge(%PaymentAttempt{provider_reference: ref} = _attempt, credential) do
    # provider_reference for Flutterwave is the numeric transaction ID (data.id
    # from the charge response), stored as a string.
    case Req.get(url("/transactions/#{ref}/verify", credential),
           headers: auth_headers(credential),
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"status" => "success", "data" => data}}} ->
        translate_verify_response(data)

      {:ok, %Req.Response{status: 404}} ->
        {:error,
         %{error_class: :indeterminate, response_code: "not_found", response_message: nil}}

      {:ok, %Req.Response{status: status}} ->
        {:error,
         %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}

      {:error, _} ->
        {:error,
         %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp translate_charge_http_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => "success"} = resp}}
       ) do
    translate_momo_response(resp["data"])
  end

  defp translate_charge_http_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => "error", "message" => msg}}}
       ) do
    {:error, %{error_class: :definite_failure, response_code: "flw_error", response_message: msg}}
  end

  defp translate_charge_http_response(
         {:ok, %Req.Response{status: 400, body: %{"message" => msg}}}
       ) do
    {:error,
     %{error_class: :definite_failure, response_code: "invalid_request", response_message: msg}}
  end

  defp translate_charge_http_response({:ok, %Req.Response{status: status}}) do
    {:error,
     %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}
  end

  defp translate_charge_http_response({:error, %{reason: :timeout}}) do
    {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
  end

  defp translate_charge_http_response({:error, _}) do
    {:error,
     %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
  end

  # MoMo charge always returns pending — Flutterwave sends a USSD push to the
  # customer's phone and notifies Yagye asynchronously via webhook.
  defp translate_momo_response(%{"status" => "pending", "id" => id}) do
    {:pending, %{provider_reference: to_string(id)}}
  end

  defp translate_momo_response(%{"status" => "successful", "id" => id, "flw_ref" => flw_ref}) do
    {:ok, %{provider_reference: to_string(id), auth_code: flw_ref}}
  end

  defp translate_momo_response(%{"status" => status}) do
    {:error,
     %{error_class: :definite_failure, response_code: "flw_#{status}", response_message: nil}}
  end

  defp translate_verify_response(%{"status" => "successful", "id" => id, "flw_ref" => flw_ref}) do
    {:ok, %{provider_reference: to_string(id), auth_code: flw_ref}}
  end

  defp translate_verify_response(%{"status" => "failed", "processor_response" => msg}) do
    {:error,
     %{error_class: :definite_failure, response_code: "flw_failed", response_message: msg}}
  end

  defp translate_verify_response(%{"status" => status}) do
    {:error,
     %{error_class: :retryable_error, response_code: "flw_#{status}", response_message: nil}}
  end

  # Flutterwave takes amounts in major currency units (cedis, not pesewas).
  # All other currencies also use their major unit (dollars, not cents, etc.).
  defp to_major_units(amount_minor, _currency), do: amount_minor / 100

  defp url(path, %{"base_url" => base_url}), do: base_url <> path

  defp url(path, %{"base_url" => base_url}, type: type) do
    base_url <> path <> "?type=#{type}"
  end

  defp auth_headers(%{"secret_key" => key}), do: [{"Authorization", "Bearer #{key}"}]
end
