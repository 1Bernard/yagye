defmodule YagyeCoreWeb.Controllers.Webhooks.InternalWebhookEndpointsController do
  @moduledoc """
  Internal (service-token) API for webhook endpoint management called by yagye_portal.
  Merchant is identified by :merchant_code in the URL path.
  """

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.MerchantWebhooks

  action_fallback YagyeCoreWeb.FallbackController

  # POST /internal/merchants/:merchant_code/webhook-endpoints
  def create(conn, %{"merchant_code" => merchant_code} = params) do
    case Merchants.get_merchant(merchant_code) do
      {:ok, merchant} ->
        case MerchantWebhooks.register_endpoint(merchant, params) do
          {:ok, endpoint, signing_secret} ->
            conn
            |> put_status(201)
            |> json(%{
              id: endpoint.public_id,
              object: "webhook_endpoint",
              url: endpoint.url,
              mode: endpoint.mode,
              active: endpoint.active,
              subscribed_events: endpoint.subscribed_events,
              signing_secret: Base.encode16(signing_secret, case: :lower),
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

  # PATCH /internal/merchants/:merchant_code/webhook-endpoints/:endpoint_id
  def update(
        conn,
        %{"merchant_code" => merchant_code, "endpoint_id" => endpoint_public_id} = params
      ) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, endpoint} <- MerchantWebhooks.get_endpoint_by_public_id(endpoint_public_id),
         true <- endpoint.merchant_id == merchant.id,
         {:ok, updated} <- MerchantWebhooks.update_endpoint(endpoint, params) do
      conn
      |> put_status(200)
      |> json(%{
        id: updated.public_id,
        object: "webhook_endpoint",
        url: updated.url,
        mode: updated.mode,
        active: updated.active,
        subscribed_events: updated.subscribed_events,
        created_at: DateTime.to_iso8601(updated.inserted_at)
      })
    else
      false ->
        conn |> put_status(403) |> json(%{error: %{code: "forbidden"}})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "not_found"}})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "validation_error", details: format_errors(cs)}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "unprocessable", message: inspect(reason)}})
    end
  end

  # DELETE /internal/merchants/:merchant_code/webhook-endpoints/:endpoint_id
  def delete(conn, %{"merchant_code" => merchant_code, "endpoint_id" => endpoint_public_id}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, endpoint} <- MerchantWebhooks.get_endpoint_by_public_id(endpoint_public_id),
         true <- endpoint.merchant_id == merchant.id,
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

  # POST /internal/merchants/:merchant_code/webhook-endpoints/:endpoint_id/test
  def test(conn, %{"merchant_code" => merchant_code, "endpoint_id" => endpoint_public_id}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, endpoint} <- MerchantWebhooks.get_endpoint_by_public_id(endpoint_public_id),
         true <- endpoint.merchant_id == merchant.id do
      # Publish directly to this endpoint, bypassing the subscribed_events filter,
      # so the test button works regardless of which events the endpoint subscribes to.
      task = %{
        "endpoint_id" => endpoint.id,
        "endpoint_public_id" => endpoint.public_id,
        "url" => endpoint.url,
        "secret_encrypted" => Base.encode16(endpoint.secret_encrypted, case: :lower),
        "event_id" => Uniq.UUID.uuid7(),
        "event_type" => "test.event",
        "merchant_id" => endpoint.merchant_id,
        "merchant_code" => merchant.public_id,
        "body" => %{
          "message" => "This is a test webhook from Yagye.",
          "live" => endpoint.mode == "live"
        },
        "attempt" => 1
      }

      MerchantWebhooks.publish_delivery_task(task)

      conn |> put_status(200) |> json(%{ok: true, endpoint_id: endpoint_public_id})
    else
      false ->
        conn |> put_status(403) |> json(%{error: %{code: "forbidden"}})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "not_found"}})
    end
  end

  # POST /internal/webhook-deliveries/retry
  # Called by the portal to re-enqueue a failed delivery.
  # endpoint_id must be the public_id (whe_...) — stored in portal_webhook_deliveries.
  def retry_delivery(conn, params) do
    endpoint_id = params["endpoint_id"]
    event_id = params["event_id"]
    event_type = params["event_type"]
    attempt = (params["attempt"] || 2) |> to_string() |> String.to_integer()
    body = params["body"] || %{}

    with {:ok, endpoint} <- MerchantWebhooks.get_endpoint_by_public_id(endpoint_id),
         {:ok, merchant} <- Merchants.get_merchant_by_id(endpoint.merchant_id) do
      task = %{
        "endpoint_id" => endpoint.id,
        "endpoint_public_id" => endpoint.public_id,
        "url" => endpoint.url,
        "secret_encrypted" => Base.encode16(endpoint.secret_encrypted, case: :lower),
        "event_id" => event_id,
        "event_type" => event_type,
        "merchant_id" => endpoint.merchant_id,
        "merchant_code" => merchant.public_id,
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
