defmodule YagyeCore.Payments.Adapters.SimulatorAdapter do
  @moduledoc """
  Provider adapter for the gateway simulator.

  Calls the simulator's HTTP API and translates its vocabulary
  (AUTHORISED, DECLINED, PENDING_AUTH) into the core's result types.
  """

  @behaviour YagyeCore.Payments.ProviderAdapter

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @impl true
  def charge(%Payment{} = payment, %PaymentAttempt{} = attempt, credential) do
    body = %{
      idempotency_key: attempt.idempotency_token,
      amount_minor: payment.amount,
      currency: payment.currency,
      instrument_type: instrument_type(payment.method)
    }

    case Req.post(url("/charges", credential),
           json: body,
           headers: auth_headers(credential),
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        translate_charge_response(body)

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

  @impl true
  def query_charge(%PaymentAttempt{} = attempt, credential) do
    case Req.get(url("/charges/#{attempt.provider_reference}", credential),
           headers: auth_headers(credential)
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        translate_charge_response(body)

      {:ok, %Req.Response{status: 404}} ->
        {:error,
         %{error_class: :indeterminate, response_code: "not_found", response_message: nil}}

      {:error, _} ->
        {:error,
         %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
    end
  end

  defp translate_charge_response(%{"state" => "AUTHORISED"} = body) do
    {:ok, %{provider_reference: body["charge_ref"], auth_code: body["auth_code"]}}
  end

  defp translate_charge_response(%{"state" => "DECLINED"} = body) do
    {:error,
     %{
       error_class: :definite_failure,
       response_code: body["decline_code"],
       response_message: nil
     }}
  end

  defp translate_charge_response(%{"state" => "PENDING_AUTH"} = body) do
    {:pending, %{provider_reference: body["charge_ref"]}}
  end

  defp translate_charge_response(%{"state" => state}) do
    {:error, %{error_class: :retryable_error, response_code: state, response_message: nil}}
  end

  @impl true
  def name_enquiry(%{msisdn: msisdn, network: network}, credential) do
    body = %{network: network, msisdn: msisdn}

    case Req.post(url("/name-enquiry", credential),
           json: body,
           headers: auth_headers(credential),
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"outcome" => "found"} = body}} ->
        {:ok, %{account_name: body["account_name"], kyc_tier: derive_kyc_tier(msisdn)}}

      {:ok, %Req.Response{status: 200, body: %{"outcome" => "not_found"}}} ->
        {:error, %{response_code: "account_not_found", response_message: nil}}

      {:ok, %Req.Response{status: status}} ->
        {:error, %{response_code: "http_#{status}", response_message: nil}}

      {:error, %{reason: :timeout}} ->
        {:error, %{response_code: "timeout", response_message: nil}}

      {:error, _} ->
        {:error, %{response_code: "network_error", response_message: nil}}
    end
  end

  # Derive a simulated KYC tier from the last digit of the MSISDN.
  # Real providers return the actual tier from their KYC database.
  defp derive_kyc_tier(msisdn) do
    last = msisdn |> String.replace(~r/\D/, "") |> String.last()

    cond do
      last in ~w[0 1 2 3] -> "tier_1"
      last in ~w[4 5 6] -> "tier_2"
      true -> "tier_3"
    end
  end

  defp instrument_type(nil), do: "CARD"
  defp instrument_type("card"), do: "CARD"
  defp instrument_type("mobile_money"), do: "WALLET"
  defp instrument_type("bank_transfer"), do: "BANK"

  defp url(path, %{"base_url" => base_url}), do: base_url <> path

  defp auth_headers(%{"api_key" => api_key}), do: [{"x-api-key", api_key}]
end
