defmodule YagyeCore.Providers do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Providers.Schemas.{MerchantProviderConnection, Provider, ProviderCredential}
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Vault

  @simulator_code "simulator"

  # ── Public API ───────────────────────────────────────────────────────────────

  # Returns {provider, decrypted_credential_map} for routing a payment.
  #
  # Simulation: always uses the platform-level simulator credential — no per-merchant
  # connection required. Every merchant can use simulation mode out of the box.
  #
  # Sandbox/live: looks up merchant_provider_connections ordered by priority (lower wins).
  # The credential is fetched by (provider_id, merchant_id, mode) — merchant-level first,
  # then platform-level fallback.
  # Returns the webhook_secret for a given provider code. The secret is stored
  # in the provider's platform-level simulation credential encrypted_payload.
  def get_webhook_secret(provider_code) do
    with {:ok, provider} <- fetch_provider_by_code(provider_code),
         {:ok, credential_map} <- fetch_platform_credential(provider.id, "simulation") do
      case credential_map["webhook_secret"] do
        nil -> {:error, :no_webhook_secret}
        secret -> {:ok, secret}
      end
    end
  end

  def get_provider_for_payment(%{mode: "simulation"}) do
    with {:ok, provider} <- fetch_provider_by_code(@simulator_code),
         {:ok, credential_map} <- fetch_platform_credential(provider.id, "simulation") do
      {:ok, {provider, credential_map}}
    end
  end

  def get_provider_for_payment(%{mode: mode, merchant_id: merchant_id})
      when mode in ["sandbox", "live"] do
    connection =
      from(c in MerchantProviderConnection,
        where:
          c.merchant_id == ^merchant_id and
            c.mode == ^mode and
            c.status == "active",
        order_by: [asc: c.priority],
        limit: 1,
        preload: [:provider]
      )
      |> Repo.one()

    case connection do
      nil ->
        {:error, {:no_provider_for_mode, mode}}

      conn ->
        with {:ok, credential_map} <- fetch_credential(conn.provider_id, merchant_id, mode) do
          {:ok, {conn.provider, credential_map}}
        end
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp fetch_provider_by_code(code) do
    case Repo.get_by(Provider, code: code, active: true) do
      nil -> {:error, :no_provider}
      provider -> {:ok, provider}
    end
  end

  # Fetch merchant-level credential first; fall back to platform-level (merchant_id IS NULL).
  defp fetch_credential(provider_id, merchant_id, mode) do
    credential =
      from(c in ProviderCredential,
        where:
          c.provider_id == ^provider_id and
            c.mode == ^mode and
            c.active == true and
            (c.merchant_id == ^merchant_id or is_nil(c.merchant_id)),
        order_by: [desc_nulls_last: c.merchant_id],
        limit: 1
      )
      |> Repo.one()

    case credential do
      nil -> {:error, :no_credential}
      cred -> decrypt_credential(cred)
    end
  end

  defp fetch_platform_credential(provider_id, mode) do
    credential =
      from(c in ProviderCredential,
        where:
          c.provider_id == ^provider_id and
            is_nil(c.merchant_id) and
            c.mode == ^mode and
            c.active == true
      )
      |> Repo.one()

    case credential do
      nil -> {:error, :no_credential}
      cred -> decrypt_credential(cred)
    end
  end

  defp decrypt_credential(%ProviderCredential{base_url: base_url, encrypted_payload: payload}) do
    case Vault.decrypt_map(payload) do
      {:ok, map} -> {:ok, Map.put(map, "base_url", base_url)}
      {:error, _} = err -> err
    end
  end
end
