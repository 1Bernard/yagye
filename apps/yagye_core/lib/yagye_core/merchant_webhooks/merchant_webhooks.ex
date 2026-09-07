defmodule YagyeCore.MerchantWebhooks do
  @moduledoc """
  Domain context for outbound merchant webhook endpoints and delivery dispatch.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.MerchantWebhooks.RabbitMQ.Publisher
  alias YagyeCore.MerchantWebhooks.Schemas.MerchantWebhookEndpoint
  alias YagyeCore.Outbox
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Vault

  # ── Endpoint CRUD ─────────────────────────────────────────────────────────────

  def register_endpoint(merchant, attrs) do
    signing_secret = :crypto.strong_rand_bytes(32)

    with {:ok, encrypted} <- Vault.encrypt(signing_secret) do
      changeset =
        MerchantWebhookEndpoint.changeset(%MerchantWebhookEndpoint{}, %{
          public_id: "whe_#{Uniq.UUID.uuid7()}",
          merchant_id: merchant.id,
          mode: attrs["mode"] || "test",
          url: attrs["url"],
          subscribed_events: attrs["subscribed_events"] || [],
          secret_encrypted: encrypted
        })

      outbox_fn = fn %{endpoint: endpoint} ->
        payload = %{
          "event_type" => "webhook.endpoint.registered",
          "endpoint_id" => endpoint.public_id,
          "merchant_code" => merchant.public_id,
          "url" => endpoint.url,
          "mode" => endpoint.mode,
          "active" => true,
          "subscribed_events" => endpoint.subscribed_events,
          "consecutive_failures" => 0
        }

        {:ok,
         Outbox.build_changeset(
           %{id: endpoint.id, merchant_id: merchant.id, mode: endpoint.mode, version: 1},
           "webhook.endpoint.registered",
           payload,
           destination: "kafka:yagye.webhooks.v1"
         )}
      end

      Multi.new()
      |> Multi.insert(:endpoint, changeset)
      |> Multi.run(:outbox, fn _repo, ctx -> outbox_fn.(ctx) |> then(&{:ok, &1}) end)
      |> Multi.insert(:outbox_msg, fn %{outbox: cs} -> cs end)
      |> Repo.transaction()
      |> case do
        {:ok, %{endpoint: endpoint}} -> {:ok, endpoint, signing_secret}
        {:error, :endpoint, cs, _} -> {:error, cs}
        {:error, _, reason, _} -> {:error, reason}
      end
    end
  end

  def deregister_endpoint(endpoint) do
    merchant = Repo.get!(Merchant, endpoint.merchant_id)

    outbox_cs =
      Outbox.build_changeset(
        %{id: endpoint.id, merchant_id: endpoint.merchant_id, mode: endpoint.mode, version: 1},
        "webhook.endpoint.deregistered",
        %{
          "event_type" => "webhook.endpoint.deregistered",
          "endpoint_id" => endpoint.public_id,
          "merchant_code" => merchant.public_id
        },
        destination: "kafka:yagye.webhooks.v1"
      )

    Multi.new()
    |> Multi.delete(:endpoint, endpoint)
    |> Multi.insert(:outbox_msg, outbox_cs)
    |> Repo.transaction()
    |> case do
      {:ok, %{endpoint: ep}} -> {:ok, ep}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def list_endpoints(merchant_id, mode \\ nil) do
    MerchantWebhookEndpoint
    |> where([e], e.merchant_id == ^merchant_id)
    |> then(fn q -> if mode, do: where(q, [e], e.mode == ^mode), else: q end)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  def get_endpoint_by_public_id(public_id) do
    case Repo.get_by(MerchantWebhookEndpoint, public_id: public_id) do
      nil -> {:error, :not_found}
      ep -> {:ok, ep}
    end
  end

  # ── Dispatch: fan-out an event to all matching endpoints ──────────────────────

  @doc """
  For a fired domain event, look up which merchant webhook endpoints subscribe
  to that event type and publish a delivery task to RabbitMQ for each one.
  """
  def dispatch_event(merchant_id, merchant_code, event_type, event_id, mode, payload) do
    endpoints =
      MerchantWebhookEndpoint
      |> where([e], e.merchant_id == ^merchant_id)
      |> where([e], e.mode == ^mode)
      |> where([e], e.active == true)
      |> where([e], ^event_type in e.subscribed_events or [] == e.subscribed_events)
      |> Repo.all()

    Enum.each(endpoints, fn ep ->
      task = %{
        "endpoint_id" => ep.id,
        "url" => ep.url,
        # Hex-encode binary so JSON-serialisable; producer decodes back to binary
        "secret_encrypted" => Base.encode16(ep.secret_encrypted, case: :lower),
        "event_id" => event_id,
        "event_type" => event_type,
        "merchant_id" => merchant_id,
        "merchant_code" => merchant_code,
        "body" => payload,
        "attempt" => 1
      }

      case Publisher.publish(task) do
        :ok ->
          :ok

        {:error, reason} ->
          require Logger

          Logger.error("Failed to publish webhook delivery task",
            endpoint_id: ep.id,
            event_id: event_id,
            reason: inspect(reason)
          )
      end
    end)

    :ok
  end
end
