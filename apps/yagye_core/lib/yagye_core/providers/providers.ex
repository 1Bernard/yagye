defmodule YagyeCore.Providers do
  @moduledoc false

  import Ecto.Query

  require Logger

  alias YagyeCore.Providers.Schemas.{MerchantProviderConnection, Provider, ProviderCredential}
  alias YagyeCore.Repo
  alias YagyeCore.Routing
  alias YagyeCore.Shared.Vault

  @simulator_code "simulator"

  # ── Public API ───────────────────────────────────────────────────────────────

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

  # For sandbox/live payments we try routing rules first, then fall back to static
  # priority ordering from merchant_provider_connections.
  #
  # Routing rules are evaluated using payment attributes (method, currency, amount).
  # When a rule matches, it returns a specific provider_id plus which rule and
  # configuration drove the decision — stored on the payment attempt for audit.
  #
  # Static fallback: lowest-priority active connection for this merchant + mode.
  # This is the pre-orchestration behaviour and remains correct for merchants with
  # no published routing configuration.
  #
  # Return: {:ok, {provider, credential_map, routing_meta}}
  # routing_meta = %{source: :rule, rule_id: id, configuration_id: config_id}
  #              | %{source: :static}
  def get_provider_for_payment(%{mode: "simulation"}, _excluded) do
    with {:ok, provider} <- fetch_provider_by_code(@simulator_code),
         {:ok, credential_map} <- fetch_platform_credential(provider.id, "simulation") do
      {:ok, {provider, credential_map, %{source: :static}}}
    end
  end

  def get_provider_for_payment(%{mode: mode, merchant_id: merchant_id} = payment, excluded)
      when mode in ["sandbox", "live"] do
    attrs = routing_attrs_for(payment)

    case Routing.evaluate(merchant_id, mode, attrs, excluded) do
      {:ok, {provider_id, rule_id, config_id}} ->
        Logger.info("[routing] rule_match merchant=#{merchant_id} rule=#{rule_id}")

        with {:ok, provider} <- fetch_provider_by_id(provider_id),
             {:ok, credential_map} <- fetch_credential(provider_id, merchant_id, mode) do
          meta = %{source: :rule, rule_id: rule_id, configuration_id: config_id}
          {:ok, {provider, credential_map, meta}}
        end

      {:error, reason} when reason in [:no_matching_rule, :rule_has_no_actions] ->
        Logger.debug(
          "[routing] no_rule_match merchant=#{merchant_id} reason=#{reason} using static priority"
        )

        static_priority_provider(merchant_id, mode, excluded)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp static_priority_provider(merchant_id, mode, excluded) do
    query =
      from(c in MerchantProviderConnection,
        where:
          c.merchant_id == ^merchant_id and
            c.mode == ^mode and
            c.status == "active",
        order_by: [asc: c.priority],
        preload: [:provider]
      )

    query =
      if excluded == [] do
        query
      else
        where(query, [c], c.provider_id not in ^excluded)
      end

    case Repo.one(from q in query, limit: 1) do
      nil ->
        {:error, {:no_provider_for_mode, mode}}

      conn ->
        with {:ok, credential_map} <- fetch_credential(conn.provider_id, merchant_id, mode) do
          {:ok, {conn.provider, credential_map, %{source: :static}}}
        end
    end
  end

  defp routing_attrs_for(%{method: method, currency: currency, amount: amount}) do
    %{
      method: method,
      currency: currency,
      # amount supports simple comparisons (eq/gt/gte/lt/lte)
      # amount_min/amount_max support range conditions: both are set to the payment
      # amount so a rule can check "amount >= X AND amount <= Y" using two conditions.
      amount: amount,
      amount_min: amount,
      amount_max: amount
    }
  end

  defp routing_attrs_for(_payment), do: %{}

  # Fetches the decrypted credential for a specific provider. Used by
  # PaymentStatusCheckWorker to re-auth with the exact same provider that
  # handled the original attempt, bypassing routing evaluation.
  def fetch_credential_for_status_check(provider_id, merchant_id, mode) do
    fetch_credential(provider_id, merchant_id, mode)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp fetch_provider_by_code(code) do
    case Repo.get_by(Provider, code: code, active: true) do
      nil -> {:error, :no_provider}
      provider -> {:ok, provider}
    end
  end

  defp fetch_provider_by_id(id) do
    case Repo.get(Provider, id) do
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
