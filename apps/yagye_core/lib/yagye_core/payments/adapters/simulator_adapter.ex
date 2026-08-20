defmodule YagyeCore.Payments.Adapters.SimulatorAdapter do
  @moduledoc """
  Provider adapter for the gateway simulator.

  Calls the simulator's HTTP API and translates its vocabulary
  (AUTHORISED, DECLINED, PENDING_AUTH) into the core's result types.
  """

  @behaviour YagyeCore.Payments.ProviderAdapter

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @impl true
  def charge(%Payment{} = payment, %PaymentAttempt{} = attempt) do
    body = %{
      idempotency_key: attempt.idempotency_token,
      amount_minor: payment.amount,
      currency: payment.currency,
      instrument_type: instrument_type(payment.method)
    }

    started_at = System.monotonic_time(:millisecond)

    case Req.post(url("/charges"), json: body, headers: auth_headers(), receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        latency = System.monotonic_time(:millisecond) - started_at
        translate_charge_response(body, latency)

      {:ok, %Req.Response{status: status}} ->
        {:error, %{error_class: :retryable_error, response_code: "http_#{status}", response_message: nil}}

      {:error, %{reason: :timeout}} ->
        {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}

      {:error, _} ->
        {:error, %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
    end
  end

  @impl true
  def query_charge(%PaymentAttempt{} = attempt) do
    case Req.get(url("/charges/#{attempt.provider_reference}"), headers: auth_headers()) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        translate_charge_response(body, nil)

      {:ok, %Req.Response{status: 404}} ->
        {:error, %{error_class: :indeterminate, response_code: "not_found", response_message: nil}}

      {:error, _} ->
        {:error, %{error_class: :indeterminate, response_code: "network_error", response_message: nil}}
    end
  end

  defp translate_charge_response(%{"state" => "AUTHORISED"} = body, _latency) do
    {:ok, %{provider_reference: body["charge_ref"], auth_code: body["auth_code"]}}
  end

  defp translate_charge_response(%{"state" => "DECLINED"} = body, _latency) do
    {:error, %{
      error_class: :definite_failure,
      response_code: body["decline_code"],
      response_message: nil
    }}
  end

  defp translate_charge_response(%{"state" => "PENDING_AUTH"}, _latency) do
    {:error, %{error_class: :indeterminate, response_code: "pending_auth", response_message: nil}}
  end

  defp translate_charge_response(%{"state" => state}, _latency) do
    {:error, %{error_class: :retryable_error, response_code: state, response_message: nil}}
  end

  defp instrument_type(nil), do: "CARD"
  defp instrument_type("card"), do: "CARD"
  defp instrument_type("mobile_money"), do: "WALLET"
  defp instrument_type("bank_transfer"), do: "BANK"

  defp url(path), do: simulator_base_url() <> path

  defp simulator_base_url do
    Application.get_env(:yagye_core, :simulator_base_url, "http://localhost:4100")
  end

  defp auth_headers do
    key = Application.get_env(:yagye_core, :simulator_api_key, "sim_dev_key")
    [{"x-api-key", key}]
  end
end
