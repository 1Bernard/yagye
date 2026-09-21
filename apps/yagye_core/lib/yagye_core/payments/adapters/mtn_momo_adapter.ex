defmodule YagyeCore.Payments.Adapters.MTNMomoAdapter do
  @moduledoc """
  Native-rail adapter for MTN Mobile Money (Ghana, direct integration).

  Uses the MTN MoMo Developer API (momodeveloper.mtn.com).
  Implements both the Collections product (inbound — customer pays Yagye) and
  the Disbursements product (outbound — Yagye pays merchant settlement).

  ## Authentication
  MTN uses OAuth2. Each API call requires a Bearer token fetched fresh per request.
  Collections: POST /collection/token/
  Disbursements: POST /disbursement/token/
  Both use HTTP Basic auth (api_user_id:api_key) + the product-specific
  Ocp-Apim-Subscription-Key. Tokens expire in 3600 seconds.

  ## Collections flow (inbound — charge/query_charge)
  1. charge/3 → POST /collection/v1_0/requesttopay (202 Accepted, async)
  2. query_charge/2 → GET /collection/v1_0/requesttopay/:ref

  ## Disbursements flow (outbound — disburse/2)
  1. disburse/2 → POST /disbursement/v1_0/transfer (202 Accepted, async)
     Returns {:pending, %{provider_reference: ref}} — BankDispatchWorker retries
     until the transfer is terminal.

  ## Credentials (stored in provider_credentials.encrypted_payload)
  - "base_url"                      — e.g. "https://sandbox.momodeveloper.mtn.com"
  - "subscription_key"              — Collections Ocp-Apim-Subscription-Key
  - "api_user_id"                   — Collections API user UUID
  - "api_key"                       — Collections API key
  - "disbursement_subscription_key" — Disbursements Ocp-Apim-Subscription-Key
                                       (falls back to subscription_key if not set)
  - "disbursement_api_user_id"      — Disbursements API user UUID
                                       (falls back to api_user_id if not set)
  - "disbursement_api_key"          — Disbursements API key
                                       (falls back to api_key if not set)
  - "target_environment"            — "sandbox" or "production"

  ## Sandbox currency quirk
  MTN's generic sandbox only accepts EUR. GHS is production-only.

  ## Provisioning (one-time, per product)
  1. Subscribe to "Collections" → get subscription_key; provision API user
  2. Subscribe to "Disbursements" → get disbursement_subscription_key; provision API user
  Both products can share the same API user UUID in sandbox (optional).
  """

  @behaviour YagyeCore.Payments.ProviderAdapter

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  # ── Public callbacks ──────────────────────────────────────────────────────────

  @impl true
  def charge(%Payment{method: "mobile_money"} = payment, %PaymentAttempt{} = attempt, credential) do
    with {:ok, token} <- fetch_token(credential) do
      msisdn = normalise_msisdn(get_in(payment.metadata, ["msisdn"]) || "")
      amount_str = to_major_units_str(payment.amount, payment.currency)

      body = %{
        "amount" => amount_str,
        "currency" => payment.currency,
        "externalId" => attempt.idempotency_token,
        "payer" => %{
          "partyIdType" => "MSISDN",
          "partyId" => msisdn
        },
        "payerMessage" => get_in(payment.metadata, ["description"]) || "Payment",
        "payeeNote" => attempt.idempotency_token
      }

      reference_id = attempt.idempotency_token

      Req.post(
        collection_url(credential, "/requesttopay"),
        json: body,
        headers: api_headers(credential, token, reference_id),
        receive_timeout: 15_000
      )
      |> translate_charge_response(reference_id)
    end
  end

  def charge(%Payment{}, %PaymentAttempt{}, _credential) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "method_not_supported",
       response_message: "MTN MoMo adapter only supports mobile_money payments"
     }}
  end

  @impl true
  def query_charge(%PaymentAttempt{provider_reference: ref} = _attempt, credential) do
    with {:ok, token} <- fetch_token(credential) do
      Req.get(
        collection_url(credential, "/requesttopay/#{ref}"),
        headers: api_headers(credential, token, nil),
        receive_timeout: 10_000
      )
      |> translate_query_response()
    end
  end

  @impl true
  def name_enquiry(%{msisdn: msisdn, network: _network}, credential) do
    with {:ok, token} <- fetch_token(credential) do
      msisdn = normalise_msisdn(msisdn)

      Req.get(
        collection_url(credential, "/accountholder/msisdn/#{msisdn}/basicuserinfo"),
        headers: api_headers(credential, token, nil),
        receive_timeout: 10_000
      )
      |> translate_name_enquiry_response()
    end
  end

  @impl true
  def disburse(
        %{amount: amount, currency: currency, reference: ref, recipient_msisdn: msisdn},
        credential
      ) do
    with {:ok, token} <- fetch_disbursement_token(credential) do
      # MTN requires X-Reference-Id to be a UUID v4. Batch IDs are UUID v7 which
      # the sandbox rejects with a silent 400. Generate a fresh v4 for the header
      # and use the batch id as externalId for idempotency tracing.
      reference_id = uuid4()

      body = %{
        "amount" => to_major_units_str(amount, currency),
        "currency" => currency,
        "externalId" => to_string(ref),
        "payee" => %{
          "partyIdType" => "MSISDN",
          "partyId" => normalise_msisdn(msisdn)
        },
        "payerMessage" => "Settlement payment",
        "payeeNote" => "Yagye settlement #{ref}"
      }

      disbursement_sub_key =
        credential["disbursement_subscription_key"] || credential["subscription_key"]

      Req.post(
        disbursement_url(credential, "/transfer"),
        json: body,
        headers: disbursement_headers(credential, token, reference_id, disbursement_sub_key),
        receive_timeout: 15_000
      )
      |> translate_disburse_response(reference_id)
    end
  end

  # ── Token management ──────────────────────────────────────────────────────────

  defp fetch_disbursement_token(credential) do
    base_url = credential["base_url"]
    user_id = credential["disbursement_api_user_id"] || credential["api_user_id"]
    api_key = credential["disbursement_api_key"] || credential["api_key"]
    sub_key = credential["disbursement_subscription_key"] || credential["subscription_key"]
    encoded = Base.encode64("#{user_id}:#{api_key}")

    Req.post("#{base_url}/disbursement/token/",
      body: "",
      headers: [
        {"Authorization", "Basic #{encoded}"},
        {"Ocp-Apim-Subscription-Key", sub_key},
        {"Content-Length", "0"}
      ],
      receive_timeout: 10_000
    )
    |> parse_disbursement_token_response()
  end

  defp parse_disbursement_token_response(
         {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}}
       ),
       do: {:ok, token}

  defp parse_disbursement_token_response({:ok, %Req.Response{status: status, body: body}}) do
    msg = extract_error_message(body, "token_error")

    {:error,
     %{
       error_class: :retryable_error,
       response_code: "disb_token_http_#{status}",
       response_message: msg
     }}
  end

  defp parse_disbursement_token_response({:error, %{reason: :timeout}}),
    do: {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}

  defp parse_disbursement_token_response({:error, _}),
    do:
      {:error,
       %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}

  defp extract_error_message(body, default) when is_map(body),
    do: body["message"] || body["error_description"] || default

  defp extract_error_message(_body, default), do: default

  defp fetch_token(%{
         "base_url" => base_url,
         "subscription_key" => sub_key,
         "api_user_id" => user_id,
         "api_key" => api_key
       }) do
    credentials = Base.encode64("#{user_id}:#{api_key}")

    case Req.post("#{base_url}/collection/token/",
           body: "",
           headers: [
             {"Authorization", "Basic #{credentials}"},
             {"Ocp-Apim-Subscription-Key", sub_key},
             {"Content-Length", "0"}
           ],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %Req.Response{status: status, body: body}} ->
        msg = (is_map(body) && (body["message"] || body["error_description"])) || "token_error"

        {:error,
         %{
           error_class: :retryable_error,
           response_code: "token_http_#{status}",
           response_message: msg
         }}

      {:error, %{reason: :timeout}} ->
        {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}

      {:error, _} ->
        {:error,
         %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
    end
  end

  # ── Response translators ──────────────────────────────────────────────────────

  # MTN returns 202 Accepted on successful initiation (no body).
  # X-Reference-Id we sent becomes the lookup key for query_charge.
  defp translate_charge_response({:ok, %Req.Response{status: 202}}, reference_id) do
    {:pending, %{provider_reference: reference_id}}
  end

  defp translate_charge_response(
         {:ok, %Req.Response{status: 400, body: body}},
         _ref
       ) do
    msg = extract_mtn_error(body)

    {:error,
     %{error_class: :definite_failure, response_code: "invalid_request", response_message: msg}}
  end

  defp translate_charge_response(
         {:ok, %Req.Response{status: 409, body: body}},
         _ref
       ) do
    # Conflict = duplicate X-Reference-Id. We treat this as indeterminate so the
    # caller can query the existing transaction instead of immediately failing.
    msg = extract_mtn_error(body)

    {:error,
     %{error_class: :indeterminate, response_code: "duplicate_reference", response_message: msg}}
  end

  defp translate_charge_response({:ok, %Req.Response{status: status}}, _ref) do
    {:error,
     %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}
  end

  defp translate_charge_response({:error, %{reason: :timeout}}, _ref) do
    {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
  end

  defp translate_charge_response({:error, _}, _ref) do
    {:error,
     %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
  end

  defp translate_query_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => "SUCCESSFUL"} = body}}
       ) do
    financial_id = body["financialTransactionId"]
    # provider_reference stays as the X-Reference-Id (our idempotency_token);
    # the MTN financial transaction id goes into auth_code for reconciliation.
    {:ok, %{provider_reference: body["externalId"], auth_code: financial_id}}
  end

  defp translate_query_response({:ok, %Req.Response{status: 200, body: %{"status" => "PENDING"}}}) do
    {:error, %{error_class: :retryable_error, response_code: "pending", response_message: nil}}
  end

  defp translate_query_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => "FAILED", "reason" => reason}}}
       ) do
    code = (is_map(reason) && reason["code"]) || "mtn_failed"
    msg = (is_map(reason) && reason["message"]) || nil
    {:error, %{error_class: :definite_failure, response_code: code, response_message: msg}}
  end

  defp translate_query_response({:ok, %Req.Response{status: 404}}) do
    {:error, %{error_class: :indeterminate, response_code: "not_found", response_message: nil}}
  end

  defp translate_query_response({:ok, %Req.Response{status: status}}) do
    {:error,
     %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}
  end

  defp translate_query_response({:error, %{reason: :timeout}}) do
    {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
  end

  defp translate_query_response({:error, _}) do
    {:error,
     %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
  end

  defp translate_name_enquiry_response({:ok, %Req.Response{status: 200, body: body}}) do
    name =
      body["name"] ||
        [body["given_name"], body["family_name"]] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

    {:ok, %{account_name: name, kyc_tier: nil}}
  end

  defp translate_name_enquiry_response({:ok, %Req.Response{status: 404}}) do
    {:error,
     %{error_class: :definite_failure, response_code: "account_not_found", response_message: nil}}
  end

  defp translate_name_enquiry_response({:ok, %Req.Response{status: status}}) do
    {:error,
     %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}
  end

  defp translate_name_enquiry_response({:error, _}) do
    {:error,
     %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
  end

  # ── Response translators ─────────────────────────────────────────────────────

  defp translate_disburse_response({:ok, %Req.Response{status: 202}}, ref) do
    {:pending, %{provider_reference: ref}}
  end

  defp translate_disburse_response({:ok, %Req.Response{status: 409}}, ref) do
    # Duplicate reference — treat as pending; caller can query to find current state.
    {:pending, %{provider_reference: ref}}
  end

  defp translate_disburse_response({:ok, %Req.Response{status: 400, body: body}}, _ref) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: "invalid_request",
       response_message: extract_mtn_error(body)
     }}
  end

  defp translate_disburse_response({:ok, %Req.Response{status: status}}, _ref) do
    {:error,
     %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}
  end

  defp translate_disburse_response({:error, %{reason: :timeout}}, _ref) do
    {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
  end

  defp translate_disburse_response({:error, _}, _ref) do
    {:error,
     %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp collection_url(%{"base_url" => base}, path) do
    "#{base}/collection/v1_0#{path}"
  end

  defp disbursement_url(%{"base_url" => base}, path) do
    "#{base}/disbursement/v1_0#{path}"
  end

  defp disbursement_headers(credential, token, reference_id, sub_key) do
    target = credential["target_environment"] || "sandbox"

    [
      {"Authorization", "Bearer #{token}"},
      {"X-Reference-Id", reference_id},
      {"X-Target-Environment", target},
      {"Ocp-Apim-Subscription-Key", sub_key}
    ]
  end

  defp api_headers(credential, token, reference_id) do
    target = credential["target_environment"] || "sandbox"
    sub_key = credential["subscription_key"]

    base = [
      {"Authorization", "Bearer #{token}"},
      {"X-Target-Environment", target},
      {"Ocp-Apim-Subscription-Key", sub_key},
      {"Content-Type", "application/json"}
    ]

    if reference_id do
      [{"X-Reference-Id", reference_id} | base]
    else
      base
    end
  end

  defp to_major_units_str(amount_minor, _currency) do
    # MTN expects a string, e.g. "50" or "100.50". We format without trailing zeros
    # for whole cedis, with 2dp for fractional amounts.
    major = amount_minor / 100

    if major == trunc(major) do
      to_string(trunc(major))
    else
      :erlang.float_to_binary(major, decimals: 2)
    end
  end

  defp uuid4 do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> = :crypto.strong_rand_bytes(16)

    <<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>
    |> Base.encode16(case: :lower)
    |> then(fn <<p::8-binary, q::4-binary, r::4-binary, s::4-binary, t::12-binary>> ->
      "#{p}-#{q}-#{r}-#{s}-#{t}"
    end)
  end

  defp normalise_msisdn("+" <> rest), do: rest
  defp normalise_msisdn("0" <> rest), do: "233" <> rest
  defp normalise_msisdn(msisdn), do: msisdn

  defp extract_mtn_error(body) when is_map(body) do
    body["message"] || body["errorDescription"] || body["error_description"] || "mtn_error"
  end

  defp extract_mtn_error(_), do: "mtn_error"
end
