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

  defp translate_charge_response(%{"state" => "PENDING_AUTH"}) do
    {:error, %{error_class: :indeterminate, response_code: "pending_auth", response_message: nil}}
  end

  defp translate_charge_response(%{"state" => state}) do
    {:error, %{error_class: :retryable_error, response_code: state, response_message: nil}}
  end

  defp instrument_type(nil), do: "CARD"
  defp instrument_type("card"), do: "CARD"
  defp instrument_type("mobile_money"), do: "WALLET"
  defp instrument_type("bank_transfer"), do: "BANK"

  defp url(path, %{"base_url" => base_url}), do: base_url <> path

  defp auth_headers(%{"api_key" => api_key}), do: [{"x-api-key", api_key}]
end
