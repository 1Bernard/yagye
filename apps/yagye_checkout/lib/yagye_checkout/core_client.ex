defmodule YagyeCheckout.CoreClient do
  @moduledoc false

  defp base_url, do: Application.fetch_env!(:yagye_checkout, :core_base_url)
  defp service_token, do: Application.fetch_env!(:yagye_checkout, :core_service_token)
  defp auth_headers, do: [{"x-service-token", service_token()}]

  @doc "Fetches a checkout session by raw URL token."
  def get_session(raw_token) do
    get("/internal/checkout/sessions/by-token?token=#{URI.encode_www_form(raw_token)}")
  end

  @doc "Creates a checkout session from a payment link slug. Returns token for redirect."
  def create_session_from_link(slug) do
    post("/internal/checkout/sessions/from-link", %{slug: slug})
  end

  @doc "Submits payment details for a checkout session. Returns payment_public_id."
  def pay_session(session_public_id, attrs) do
    post("/internal/checkout/sessions/#{session_public_id}/pay", attrs)
  end

  @doc "Polls the state of a payment."
  def get_payment_state(payment_public_id) do
    get("/internal/checkout/payments/#{payment_public_id}/state")
  end

  @doc "Marks a checkout session as completed once payment succeeds."
  def complete_session(session_public_id, payment_public_id) do
    post("/internal/checkout/sessions/#{session_public_id}/complete", %{
      payment_public_id: payment_public_id
    })
  end

  # ── HTTP helpers ─────────────────────────────────────────────────────────────

  defp get(path) do
    case Req.get(base_url() <> path,
           headers: auth_headers(),
           receive_timeout: 8_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{status: 422, body: body}} -> {:error, body}
      {:ok, %Req.Response{status: _}} -> {:error, :unexpected}
      {:error, _} -> {:error, :network_error}
    end
  end

  defp post(path, body) do
    case Req.post(base_url() <> path,
           json: body,
           headers: auth_headers(),
           receive_timeout: 8_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{status: 422, body: body}} -> {:error, body}
      {:ok, %Req.Response{status: _}} -> {:error, :unexpected}
      {:error, _} -> {:error, :network_error}
    end
  end
end
