defmodule YagyeCoreWeb.Controllers.Webhooks.WebhookDeliveriesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.MerchantWebhooks
  alias YagyeCoreWeb.Plugs.Authorize

  action_fallback YagyeCoreWeb.FallbackController

  plug Authorize, [scope: "webhooks:write", kind: :secret] when action in [:retry]

  def retry(conn, params) do
    merchant_id = conn.assigns.merchant_id
    endpoint_id = params["endpoint_id"]
    event_id = params["event_id"]
    event_type = params["event_type"]
    attempt = (params["attempt"] || 2) |> to_string() |> String.to_integer()
    body = params["body"] || %{}

    with {:ok, endpoint} <- MerchantWebhooks.get_endpoint_by_public_id(endpoint_id),
         true <- endpoint.merchant_id == merchant_id do
      task = %{
        "endpoint_id" => endpoint.id,
        "endpoint_public_id" => endpoint.public_id,
        "url" => endpoint.url,
        "secret_encrypted" => Base.encode16(endpoint.secret_encrypted, case: :lower),
        "event_id" => event_id,
        "event_type" => event_type,
        "merchant_id" => merchant_id,
        "merchant_code" => nil,
        "body" => body,
        "attempt" => attempt
      }

      case MerchantWebhooks.publish_delivery_task(task) do
        :ok ->
          conn |> put_status(200) |> json(%{ok: true, status: "queued"})

        {:error, reason} ->
          conn
          |> put_status(422)
          |> json(%{error: %{code: "dispatch_failed", message: inspect(reason)}})
      end
    else
      false ->
        conn |> put_status(403) |> json(%{error: %{code: "forbidden"}})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "not_found"}})
    end
  end
end
