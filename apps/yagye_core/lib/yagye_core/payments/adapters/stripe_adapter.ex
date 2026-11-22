defmodule YagyeCore.Payments.Adapters.StripeAdapter do
  @moduledoc """
  Payment adapter for Stripe (external PSP, Model B).

  Handles card and mobile money payments via Stripe's PaymentIntents API.
  Stripe requires form-encoded request bodies (application/x-www-form-urlencoded).

  ## Amount handling
  Stripe accepts amounts in MINOR units (pesewas for GHS), matching Yagye's
  internal representation. No conversion needed.

  ## Card payment flow (async)
  1. POST /v1/payment_intents — creates intent in "requires_payment_method" state
  2. Returns {:pending, ...} — merchant frontend captures card details via Stripe.js
  3. Customer completes payment → Stripe sends payment_intent.succeeded webhook
  4. Webhook processor calls handle_provider_response to complete the payment

  For test mode, pass `payment_method_id: "pm_card_visa"` in payment metadata to
  confirm synchronously (skips the frontend step).

  ## Mobile money flow (async)
  1. POST /v1/payment_intents with payment_method_types[]=mobile_money
  2. Returns {:pending, ...} — Stripe sends USSD push to customer
  3. Customer approves on phone → payment_intent.succeeded webhook

  ## Payouts (disburse/2)
  Creates a Stripe Payout to the connected bank account on the merchant's Stripe
  account. The bank account must already be attached to the Stripe account.
  Payout arrives in 1–2 business days (instant payouts available on some accounts).

  ## Credentials (stored in provider_credentials.encrypted_payload)
  - "secret_key" — Stripe secret key (sk_test_... or sk_live_...)
  - "base_url"   — defaults to "https://api.stripe.com/v1" if absent

  ## Webhook signature
  Stripe signs webhooks with HMAC-SHA256 using the endpoint's signing secret
  (stripe_webhook_secret in credentials). The signature is in the
  Stripe-Signature header.

  ## Network mapping for mobile money
  - "MTN" / "mtn"             → "mobile_money" with mtn network
  - "Vodafone" / "Telecel"    → "mobile_money" with vodafone network
  - "AirtelTigo" / "airteltigo" → "mobile_money" with airteltigo network
  """

  @behaviour YagyeCore.Payments.Providers.ProviderAdapter

  alias YagyeCore.Payments.Adapters.PspHttp
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @stripe_version "2024-06-20"

  @network_map %{
    "MTN" => "mtn",
    "Vodafone" => "vodafone",
    "VODAFONE" => "vodafone",
    "Telecel" => "vodafone",
    "TELECEL" => "vodafone",
    "AirtelTigo" => "airteltigo",
    "AIRTELTIGO" => "airteltigo",
    "mtn" => "mtn",
    "vodafone" => "vodafone",
    "telecel" => "vodafone",
    "airteltigo" => "airteltigo"
  }

  # ── charge/3 ─────────────────────────────────────────────────────────────────

  @impl true
  def charge(%Payment{method: "mobile_money"} = payment, %PaymentAttempt{} = attempt, credential) do
    network = get_in(payment.metadata, ["network"]) || "MTN"
    msisdn = get_in(payment.metadata, ["msisdn"]) || ""

    params =
      [
        {"amount", payment.amount},
        {"currency", String.downcase(payment.currency)},
        {"payment_method_types[]", "mobile_money"},
        {"payment_method_data[type]", "mobile_money"},
        {"payment_method_data[mobile_money][phone]", msisdn},
        {"payment_method_data[billing_details][phone]", msisdn},
        {"metadata[yagye_payment_id]", payment.id},
        {"metadata[yagye_attempt_id]", attempt.id},
        {"metadata[network]", Map.get(@network_map, network, "mtn")},
        {"confirm", "true"}
      ]

    stripe_post("/payment_intents", params, attempt.idempotency_token, credential)
    |> translate_intent_response()
  end

  @impl true
  def charge(%Payment{method: "card"} = payment, %PaymentAttempt{} = attempt, credential) do
    # If a payment_method_id is in metadata (test mode or pre-authenticated card),
    # confirm immediately. Otherwise create an unconfirmed intent for frontend capture.
    payment_method_id = get_in(payment.metadata, ["payment_method_id"])

    base_params = [
      {"amount", payment.amount},
      {"currency", String.downcase(payment.currency)},
      {"payment_method_types[]", "card"},
      {"metadata[yagye_payment_id]", payment.id},
      {"metadata[yagye_attempt_id]", attempt.id}
    ]

    params =
      if payment_method_id do
        base_params ++
          [
            {"payment_method", payment_method_id},
            {"confirm", "true"}
          ]
      else
        base_params
      end

    stripe_post("/payment_intents", params, attempt.idempotency_token, credential)
    |> translate_intent_response()
  end

  def charge(%Payment{} = _payment, %PaymentAttempt{} = _attempt, _credential) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "method_not_supported",
       response_message: "Only card and mobile_money are supported by the Stripe adapter"
     }}
  end

  # ── query_charge/2 ───────────────────────────────────────────────────────────

  @impl true
  def query_charge(%PaymentAttempt{provider_reference: pi_id} = _attempt, credential) do
    case stripe_get("/payment_intents/#{pi_id}", credential) do
      {:ok, %Req.Response{status: 200, body: %{"id" => _, "status" => status} = intent}} ->
        translate_intent_status(status, intent)

      {:ok, %Req.Response{status: 404}} ->
        {:error,
         %{error_class: :indeterminate, response_code: "not_found", response_message: nil}}

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

  # ── disburse/2 ───────────────────────────────────────────────────────────────

  # Stripe payouts use the merchant's connected Stripe account balance.
  # The bank account must already be attached to their Stripe account.
  @impl true
  def disburse(%{amount: amount, currency: currency, reference: ref}, credential) do
    params = [
      {"amount", amount},
      {"currency", String.downcase(currency)},
      {"metadata[yagye_reference]", ref}
    ]

    case stripe_post("/payouts", params, ref, credential) do
      {:ok, %Req.Response{status: 200, body: %{"id" => payout_id, "status" => "paid"}}} ->
        {:ok, %{provider_reference: payout_id}}

      {:ok, %Req.Response{status: 200, body: %{"id" => payout_id}}} ->
        {:pending, %{provider_reference: payout_id}}

      {:ok, %Req.Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error,
         %{
           error_class: :definite_failure,
           response_code: "payout_error",
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

  def disburse(_params, _credential) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "missing_params",
       response_message: "disburse/2 requires amount, currency, and reference"
     }}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp stripe_post(path, params, idempotency_key, credential) do
    PspHttp.post(
      url(path, credential),
      [
        form: params,
        headers:
          auth_headers(credential) ++
            [
              {"Stripe-Version", @stripe_version},
              {"Idempotency-Key", to_string(idempotency_key)}
            ],
        receive_timeout: 15_000
      ] ++ extra_req_opts()
    )
  end

  defp stripe_get(path, credential) do
    PspHttp.get(
      url(path, credential),
      [
        headers:
          auth_headers(credential) ++
            [{"Stripe-Version", @stripe_version}],
        receive_timeout: 10_000
      ] ++ extra_req_opts()
    )
  end

  defp translate_intent_response(
         {:ok, %Req.Response{status: 200, body: %{"id" => pi_id, "status" => status} = intent}}
       ) do
    translate_intent_status(status, Map.put(intent, "id", pi_id))
  end

  defp translate_intent_response(
         {:ok, %Req.Response{status: status, body: %{"error" => %{"message" => msg}}}}
       )
       when status in [400, 402] do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "stripe_error",
       response_message: msg
     }}
  end

  defp translate_intent_response({:ok, %Req.Response{status: status}})
       when status >= 500 do
    {:error,
     %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}
  end

  defp translate_intent_response({:ok, %Req.Response{status: status}}) do
    {:error,
     %{error_class: :definite_failure, response_code: "http_#{status}", response_message: nil}}
  end

  defp translate_intent_response({:error, %{reason: :timeout}}) do
    {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
  end

  defp translate_intent_response({:error, _}) do
    {:error,
     %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
  end

  defp translate_intent_status("succeeded", %{"id" => pi_id} = intent) do
    charge_id =
      get_in(intent, ["latest_charge"]) ||
        get_in(intent, ["charges", "data", Access.at(0), "id"])

    {:ok, %{provider_reference: pi_id, auth_code: charge_id}}
  end

  defp translate_intent_status(status, %{"id" => pi_id})
       when status in [
              "requires_payment_method",
              "requires_confirmation",
              "requires_action",
              "processing"
            ] do
    {:pending, %{provider_reference: pi_id}}
  end

  defp translate_intent_status("canceled", %{"cancellation_reason" => reason}) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "canceled",
       response_message: reason
     }}
  end

  defp translate_intent_status("canceled", _intent) do
    {:error, %{error_class: :definite_failure, response_code: "canceled", response_message: nil}}
  end

  defp translate_intent_status(status, _intent) do
    {:error,
     %{error_class: :retryable_error, response_code: "intent_#{status}", response_message: nil}}
  end

  defp url(path, %{"base_url" => base_url}), do: base_url <> path
  defp url(path, _), do: "https://api.stripe.com/v1" <> path

  defp auth_headers(%{"secret_key" => key}),
    do: [{"Authorization", "Bearer #{key}"}]

  defp extra_req_opts, do: Application.get_env(:yagye_core, :stripe_req_opts, [])
end
