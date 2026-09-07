defmodule YagyeCoreWeb.Controllers.Webhooks.WebhookEndpointsController do
  @moduledoc """
  v1 API for merchant webhook endpoint management.
  Merchant authenticates with their secret API key (scoped `webhooks:write`).
  """

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.MerchantWebhooks
  alias YagyeCoreWeb.Plugs.Authorize

  action_fallback YagyeCoreWeb.FallbackController

  plug Authorize, [scope: "webhooks:write", kind: :secret] when action in [:create, :delete]

  def create(conn, params) do
    merchant_id = conn.assigns.merchant_id

    case Merchants.get_merchant_by_id(merchant_id) do
      {:ok, merchant} ->
        case MerchantWebhooks.register_endpoint(merchant, params) do
          {:ok, endpoint, _signing_secret} ->
            conn
            |> put_status(201)
            |> json(%{
              id: endpoint.public_id,
              object: "webhook_endpoint",
              url: endpoint.url,
              mode: endpoint.mode,
              active: endpoint.active,
              subscribed_events: endpoint.subscribed_events,
              created_at: DateTime.to_iso8601(endpoint.inserted_at)
            })

          {:error, %Ecto.Changeset{} = cs} ->
            conn
            |> put_status(422)
            |> json(%{error: %{code: "validation_error", details: format_errors(cs)}})

          {:error, reason} ->
            conn
            |> put_status(422)
            |> json(%{error: %{code: "unprocessable", message: inspect(reason)}})
        end

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "merchant_not_found"}})
    end
  end

  def delete(conn, %{"endpoint_id" => endpoint_public_id}) do
    with {:ok, endpoint} <- MerchantWebhooks.get_endpoint_by_public_id(endpoint_public_id),
         true <- endpoint.merchant_id == conn.assigns.merchant_id,
         {:ok, _} <- MerchantWebhooks.deregister_endpoint(endpoint) do
      conn |> put_status(200) |> json(%{id: endpoint_public_id, deleted: true})
    else
      false ->
        conn |> put_status(403) |> json(%{error: %{code: "forbidden"}})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "not_found"}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "unprocessable", message: inspect(reason)}})
    end
  end

  def test(conn, %{"endpoint_id" => endpoint_public_id}) do
    with {:ok, endpoint} <- MerchantWebhooks.get_endpoint_by_public_id(endpoint_public_id),
         true <- endpoint.merchant_id == conn.assigns.merchant_id,
         {:ok, merchant} <- Merchants.get_merchant_by_id(conn.assigns.merchant_id) do
      MerchantWebhooks.dispatch_event(
        endpoint.merchant_id,
        merchant.public_id,
        "test.event",
        Uniq.UUID.uuid7(),
        endpoint.mode,
        %{"message" => "This is a test webhook from Yagye.", "live" => endpoint.mode == "live"}
      )

      conn |> put_status(200) |> json(%{ok: true, endpoint_id: endpoint_public_id})
    else
      false ->
        conn |> put_status(403) |> json(%{error: %{code: "forbidden"}})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "not_found"}})
    end
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
