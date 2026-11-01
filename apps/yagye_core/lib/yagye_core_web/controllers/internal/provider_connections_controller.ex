defmodule YagyeCoreWeb.Controllers.Internal.ProviderConnectionsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Providers
  alias YagyeCore.Repo
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def index(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, merchant} <- resolve_merchant(merchant_code) do
      {:ok, connections} = Providers.list_merchant_connections(merchant.id, params["mode"])

      Response.ok(conn, %{
        object: "list",
        count: length(connections),
        data: Enum.map(connections, &connection_json/1)
      })
    end
  end

  def create(conn, params) do
    merchant_code = params["merchant_code"]
    provider_code = params["provider_code"]
    mode = params["mode"] || "sandbox"
    priority = params["priority"] || 1
    enabled_methods = params["enabled_methods"] || []

    with {:ok, merchant} <- resolve_merchant(merchant_code),
         {:ok, provider} <- resolve_provider(provider_code),
         {:ok, connection} <-
           Providers.create_merchant_connection(merchant.id, provider.id, %{
             mode: mode,
             priority: priority,
             enabled_methods: enabled_methods,
             status: "active"
           }),
         {:ok, _cred} <- maybe_store_credential(provider, merchant, mode, params) do
      conn
      |> put_status(:created)
      |> json(connection_json(connection))
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs =
      %{}
      |> maybe_put("priority", params["priority"])
      |> maybe_put("status", params["status"])
      |> maybe_put("enabled_methods", params["enabled_methods"])

    with {:ok, connection} <- Providers.update_merchant_connection(id, attrs) do
      Response.ok(conn, connection_json(connection))
    end
  end

  def deactivate(conn, %{"id" => id}) do
    with {:ok, connection} <- Providers.deactivate_merchant_connection(id) do
      Response.ok(conn, connection_json(connection))
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp resolve_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  defp resolve_provider(code) do
    case Providers.get_provider_by_code(code) do
      {:ok, _} = ok -> ok
      _ -> {:error, :not_found}
    end
  end

  defp maybe_store_credential(provider, merchant, mode, params) do
    api_key = params["api_key"]
    secret_key = params["secret_key"]
    base_url = params["base_url"] || ""

    if api_key || secret_key do
      credential_map = %{
        "base_url" => base_url,
        "api_key" => api_key,
        "secret_key" => secret_key
      }

      Providers.store_merchant_credential(provider.id, merchant.id, mode, credential_map)
    else
      {:ok, :no_credential}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp connection_json(c) do
    %{
      object: "provider_connection",
      id: c.id,
      merchant_id: c.merchant_id,
      provider_id: c.provider_id,
      provider_code: c.provider && c.provider.code,
      provider_name: c.provider && c.provider.display_name,
      provider_kind: c.provider && c.provider.kind,
      mode: c.mode,
      priority: c.priority,
      enabled_methods: c.enabled_methods,
      status: c.status,
      inserted_at: c.inserted_at
    }
  end
end
