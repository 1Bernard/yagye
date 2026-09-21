defmodule YagyeCore.Payments.Adapters.PaystackAdapter do
  @moduledoc """
  Payment adapter for Paystack (external PSP, Model B).

  Handles mobile money payments in Ghana (GHS) via Paystack's charge API.
  Card support is deferred — Paystack card charges require redirect / hosted flows.

  ## Amount handling
  Paystack accepts amounts in MINOR units (pesewas for GHS), matching Yagye's
  internal representation. No conversion needed.

  ## Mobile money flow (async)
  1. POST /charge with mobile_money object → Paystack sends USSD push to customer
  2. Returns {:pending, ...} — payment is in requires_action state
  3. Customer approves on phone → Paystack sends charge.success webhook
  4. Webhook processor calls handle_provider_response to complete the payment

  ## Bank disbursement flow (disburse/2)
  Used by BankDispatchWorker to settle merchant funds to a bank account.
  1. POST /transferrecipient — creates (or fetches existing) recipient for the account
  2. POST /transfer — initiates the transfer from Yagye's Paystack balance
  3. Returns {:pending, ...} — Paystack processes async; webhook or polling confirms

  ## Credentials (stored in provider_credentials.encrypted_payload)
  - "secret_key" — Paystack secret key (sk_test_... or sk_live_...)
  - "public_key" — Paystack public key (optional, not needed for server calls)
  - "base_url"   — defaults to "https://api.paystack.co" if absent

  The HMAC-SHA512 webhook signature uses the "secret_key" as the key.

  ## Network codes
  Ghana MoMo networks in Paystack:
  - "mtn"        → MTN Mobile Money
  - "vod"        → Vodafone Cash
  - "airteltigo" → AirtelTigo Money
  """

  @behaviour YagyeCore.Payments.ProviderAdapter

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @network_map %{
    "MTN" => "mtn",
    "Vodafone" => "vod",
    "AirtelTigo" => "airteltigo",
    "mtn" => "mtn",
    "vodafone" => "vod",
    "airteltigo" => "airteltigo"
  }

  @impl true
  def charge(%Payment{method: "mobile_money"} = payment, %PaymentAttempt{} = attempt, credential) do
    network = get_in(payment.metadata, ["network"]) || "MTN"
    msisdn = get_in(payment.metadata, ["msisdn"]) || ""
    email = get_in(payment.metadata, ["email"]) || "payments@yagye.com"

    body = %{
      amount: payment.amount,
      email: email,
      currency: payment.currency,
      reference: attempt.idempotency_token,
      mobile_money: %{
        phone: msisdn,
        provider: Map.get(@network_map, network, "mtn")
      }
    }

    Req.post(url("/charge", credential),
      json: body,
      headers: auth_headers(credential),
      receive_timeout: 15_000
    )
    |> translate_charge_http_response()
  end

  def charge(%Payment{} = _payment, %PaymentAttempt{} = _attempt, _credential) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "method_not_supported",
       response_message: "Use hosted checkout for Paystack card/bank payments"
     }}
  end

  @impl true
  def query_charge(%PaymentAttempt{provider_reference: ref} = _attempt, credential) do
    # provider_reference for Paystack is the transaction reference string —
    # the same idempotency_token we passed as the charge reference.
    case Req.get(url("/transaction/verify/#{ref}", credential),
           headers: auth_headers(credential),
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"status" => true, "data" => data}}} ->
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

  @impl true
  def disburse(
        %{
          amount: amount,
          currency: currency,
          reference: ref,
          recipient_bank_code: bank_code,
          recipient_account_number: account_number,
          recipient_name: name
        },
        credential
      ) do
    with {:ok, recipient_code} <-
           ensure_recipient(bank_code, account_number, name, currency, credential),
         {:ok, transfer_code} <-
           initiate_transfer(amount, currency, ref, recipient_code, credential) do
      {:pending, %{provider_reference: transfer_code}}
    end
  end

  def disburse(_params, _credential) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "missing_bank_params",
       response_message:
         "disburse/2 requires recipient_bank_code, recipient_account_number, recipient_name"
     }}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp ensure_recipient(bank_code, account_number, name, currency, credential) do
    body = %{
      type: "ghipss",
      name: name,
      account_number: account_number,
      bank_code: bank_code,
      currency: currency
    }

    case Req.post(url("/transferrecipient", credential),
           json: body,
           headers: auth_headers(credential),
           receive_timeout: 15_000
         ) do
      {:ok,
       %Req.Response{
         status: status,
         body: %{"status" => true, "data" => %{"recipient_code" => code}}
       }}
      when status in [200, 201] ->
        {:ok, code}

      {:ok, %Req.Response{status: _, body: %{"status" => false, "message" => msg}}} ->
        {:error,
         %{
           error_class: :definite_failure,
           response_code: "recipient_error",
           response_message: msg
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error,
         %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}

      {:error, %{reason: :timeout}} ->
        {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}

      {:error, _} ->
        {:error,
         %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
    end
  end

  defp initiate_transfer(amount, currency, reference, recipient_code, credential) do
    body = %{
      source: "balance",
      amount: amount,
      currency: currency,
      reference: reference,
      recipient: recipient_code,
      reason: "Yagye settlement #{reference}"
    }

    case Req.post(url("/transfer", credential),
           json: body,
           headers: auth_headers(credential),
           receive_timeout: 15_000
         ) do
      {:ok,
       %Req.Response{
         status: status,
         body: %{"status" => true, "data" => %{"transfer_code" => code}}
       }}
      when status in [200, 201] ->
        {:ok, code}

      # Duplicate reference — transfer already exists; treat as pending.
      {:ok,
       %Req.Response{status: _, body: %{"status" => false, "message" => "Duplicate request" <> _}}} ->
        {:error,
         %{
           error_class: :indeterminate,
           response_code: "duplicate_reference",
           response_message: nil
         }}

      {:ok, %Req.Response{status: _, body: %{"status" => false, "message" => msg}}} ->
        {:error,
         %{error_class: :definite_failure, response_code: "transfer_error", response_message: msg}}

      {:ok, %Req.Response{status: status}} ->
        {:error,
         %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}

      {:error, %{reason: :timeout}} ->
        {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}

      {:error, _} ->
        {:error,
         %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
    end
  end

  defp translate_charge_http_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => true, "data" => data}}}
       ) do
    translate_charge_response(data)
  end

  defp translate_charge_http_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => false, "message" => msg}}}
       ) do
    {:error,
     %{error_class: :definite_failure, response_code: "paystack_error", response_message: msg}}
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

  defp translate_charge_response(%{"status" => "pending", "reference" => ref}) do
    {:pending, %{provider_reference: ref}}
  end

  defp translate_charge_response(%{"status" => "success", "reference" => ref}) do
    {:ok, %{provider_reference: ref, auth_code: nil}}
  end

  defp translate_charge_response(%{"status" => "failed", "gateway_response" => msg}) do
    {:error, %{error_class: :definite_failure, response_code: "ps_failed", response_message: msg}}
  end

  defp translate_charge_response(%{"status" => status}) do
    {:error,
     %{error_class: :retryable_error, response_code: "ps_#{status}", response_message: nil}}
  end

  defp translate_verify_response(%{"status" => "success", "reference" => ref}) do
    {:ok, %{provider_reference: ref, auth_code: nil}}
  end

  defp translate_verify_response(%{"status" => "failed", "gateway_response" => msg}) do
    {:error, %{error_class: :definite_failure, response_code: "ps_failed", response_message: msg}}
  end

  defp translate_verify_response(%{"status" => status}) do
    {:error,
     %{error_class: :retryable_error, response_code: "ps_#{status}", response_message: nil}}
  end

  defp url(path, %{"base_url" => base_url}), do: base_url <> path
  defp url(path, _), do: "https://api.paystack.co" <> path

  defp auth_headers(%{"secret_key" => key}), do: [{"Authorization", "Bearer #{key}"}]
end
