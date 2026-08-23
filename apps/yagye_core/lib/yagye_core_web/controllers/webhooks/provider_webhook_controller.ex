defmodule YagyeCoreWeb.Controllers.Webhooks.ProviderWebhookController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Providers
  alias YagyeCore.Webhooks

  def receive(conn, %{"provider_code" => provider_code} = params) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("x-webhook-signature") |> List.first()
    event_id = params["event_id"] || conn |> get_req_header("x-webhook-event-id") |> List.first()
    event_type = params["event_type"]

    with {:ok, secret} <- Providers.get_webhook_secret(provider_code),
         :ok <- verify_signature(raw_body, signature, secret),
         true <- is_binary(event_id) and is_binary(event_type) do
      case Webhooks.receive_webhook(provider_code, event_id, event_type, raw_body) do
        {:ok, _webhook} -> send_resp(conn, 200, "")
        {:error, :already_received} -> send_resp(conn, 200, "")
        {:error, _reason} -> send_resp(conn, 422, "")
      end
    else
      {:error, :invalid_signature} -> send_resp(conn, 401, "")
      {:error, _} -> send_resp(conn, 400, "")
      false -> send_resp(conn, 422, "")
    end
  end

  defp verify_signature(_raw_body, nil, _secret), do: {:error, :invalid_signature}

  defp verify_signature(raw_body, "sha256=" <> hex, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, hex),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  defp verify_signature(_raw_body, _sig, _secret), do: {:error, :invalid_signature}
end
