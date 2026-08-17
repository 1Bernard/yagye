defmodule YagyeCore.Merchants do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Merchants.Commands.{ApproveMerchant, IssueApiKey, RegisterMerchant, RevokeApiKey}

  alias YagyeCore.Merchants.Events.{
    ApiKeyIssued,
    ApiKeyRevoked,
    MerchantApproved,
    MerchantRegistered
  }

  alias YagyeCore.Merchants.{ApiKey, Merchant, MerchantMode}
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_merchant(attrs) do
    dispatch(%RegisterMerchant{
      legal_name: Map.get(attrs, :legal_name, attrs["legal_name"]),
      trading_name: Map.get(attrs, :trading_name, attrs["trading_name"]),
      country: Map.get(attrs, :country, attrs["country"]),
      default_currency: Map.get(attrs, :default_currency, attrs["default_currency"]),
      metadata: Map.get(attrs, :metadata, attrs["metadata"])
    })
  end

  def approve(merchant_id, approved_by) do
    dispatch(%ApproveMerchant{merchant_id: merchant_id, approved_by: approved_by})
  end

  def issue_api_key(merchant_id, attrs) do
    dispatch(%IssueApiKey{
      merchant_id: merchant_id,
      mode: Map.get(attrs, :mode, attrs["mode"]),
      kind: Map.get(attrs, :kind, attrs["kind"]),
      scopes: Map.get(attrs, :scopes, attrs["scopes"]) || [],
      expires_at: Map.get(attrs, :expires_at, attrs["expires_at"]),
      created_by: Map.get(attrs, :created_by, attrs["created_by"])
    })
  end

  def revoke_api_key(api_key_id, merchant_id, revoked_by) do
    dispatch(%RevokeApiKey{
      api_key_id: api_key_id,
      merchant_id: merchant_id,
      revoked_by: revoked_by
    })
  end

  # Returns {:ok, api_key} where api_key has :merchant preloaded, or {:error, :invalid_credentials}.
  # Runs Argon2.no_user_verify/0 on miss to prevent timing-based key enumeration.
  def authenticate(raw_key) do
    key_prefix = String.slice(raw_key, 0, 24)

    case get_active_key_by_prefix(key_prefix) do
      {:ok, %ApiKey{kind: "publishable"} = api_key} ->
        if raw_key == api_key.key_prefix do
          {:ok, api_key}
        else
          Argon2.no_user_verify()
          {:error, :invalid_credentials}
        end

      {:ok, %ApiKey{kind: "secret"} = api_key} ->
        if Argon2.verify_pass(raw_key, api_key.secret_hash) do
          {:ok, api_key}
        else
          {:error, :invalid_credentials}
        end

      {:error, :not_found} ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def get_merchant(id) do
    case Repo.get(Merchant, id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  # ── Dispatch ─────────────────────────────────────────────────────────────────

  defp dispatch(%RegisterMerchant{} = cmd) do
    Repo.transaction(fn ->
      attrs = %{
        public_id: "mch_#{Uniq.UUID.uuid7()}",
        legal_name: cmd.legal_name,
        trading_name: cmd.trading_name,
        country: String.upcase(cmd.country),
        default_currency: String.upcase(cmd.default_currency),
        api_version: "2026-01-01",
        metadata: cmd.metadata || %{}
      }

      with {:ok, merchant} <- %Merchant{} |> Merchant.changeset(attrs) |> Repo.insert(),
           {:ok, _} <- grant_mode(merchant.id, :simulation) do
        event = %MerchantRegistered{
          merchant_id: merchant.id,
          public_id: merchant.public_id,
          legal_name: merchant.legal_name,
          trading_name: merchant.trading_name,
          country: merchant.country,
          default_currency: merchant.default_currency,
          occurred_at: DateTime.utc_now()
        }

        # P7: append event to outbox_messages in this same transaction
        {merchant, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp dispatch(%ApproveMerchant{} = cmd) do
    Repo.transaction(fn ->
      with {:ok, merchant} <- fetch_approvable(cmd.merchant_id),
           {:ok, merchant} <-
             merchant |> Ecto.Changeset.change(status: "approved") |> Repo.update(),
           {:ok, _} <- grant_mode(merchant.id, :live) do
        event = %MerchantApproved{
          merchant_id: merchant.id,
          approved_by: cmd.approved_by,
          occurred_at: DateTime.utc_now()
        }

        # P7: outbox
        {merchant, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp dispatch(%IssueApiKey{} = cmd) do
    Repo.transaction(fn ->
      {raw_key, key_prefix, secret_hash} = generate_key_material(cmd.kind)

      attrs = %{
        public_id: "key_#{Uniq.UUID.uuid7()}",
        merchant_id: cmd.merchant_id,
        mode: cmd.mode,
        kind: to_string(cmd.kind),
        key_prefix: key_prefix,
        secret_hash: secret_hash,
        scopes: cmd.scopes,
        expires_at: cmd.expires_at,
        created_by: cmd.created_by
      }

      case %ApiKey{} |> ApiKey.changeset(attrs) |> Repo.insert() do
        {:ok, api_key} ->
          event = %ApiKeyIssued{
            api_key_id: api_key.id,
            public_id: api_key.public_id,
            merchant_id: api_key.merchant_id,
            mode: api_key.mode,
            kind: api_key.kind,
            key_prefix: api_key.key_prefix,
            scopes: api_key.scopes,
            expires_at: api_key.expires_at,
            occurred_at: DateTime.utc_now()
          }

          # P7: outbox
          # raw_key is returned here and ONLY here — never stored, never logged
          {api_key, raw_key, event}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp dispatch(%RevokeApiKey{} = cmd) do
    Repo.transaction(fn ->
      query =
        from k in ApiKey,
          where: k.id == ^cmd.api_key_id,
          where: k.merchant_id == ^cmd.merchant_id,
          where: is_nil(k.revoked_at)

      with {:ok, api_key} <- one_or_error(query),
           {:ok, api_key} <-
             api_key
             |> Ecto.Changeset.change(revoked_at: DateTime.utc_now())
             |> Repo.update() do
        event = %ApiKeyRevoked{
          api_key_id: api_key.id,
          merchant_id: api_key.merchant_id,
          revoked_by: cmd.revoked_by,
          occurred_at: DateTime.utc_now()
        }

        # P7: outbox
        {api_key, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp grant_mode(merchant_id, mode) do
    %MerchantMode{}
    |> MerchantMode.changeset(%{
      merchant_id: merchant_id,
      mode: mode,
      enabled_at: DateTime.utc_now()
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:merchant_id, :mode])
  end

  defp fetch_approvable(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
      %Merchant{status: "registered"} = m -> {:ok, m}
      %Merchant{} -> {:error, :invalid_state}
      nil -> {:error, :not_found}
    end
  end

  defp get_active_key_by_prefix(key_prefix) do
    now = DateTime.utc_now()

    query =
      from k in ApiKey,
        where: k.key_prefix == ^key_prefix,
        where: is_nil(k.revoked_at),
        where: is_nil(k.expires_at) or k.expires_at > ^now

    one_or_error(query)
  end

  # Secret keys: 32 random bytes base64-encoded → 43-char key; first 24 stored as prefix.
  # Publishable keys: 18 random bytes → 24-char base64 = the entire key (not secret, no hash).
  defp generate_key_material("secret") do
    raw = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
    prefix = String.slice(raw, 0, 24)
    hash = Argon2.hash_pwd_salt(raw)
    {raw, prefix, hash}
  end

  defp generate_key_material("publishable") do
    raw = :crypto.strong_rand_bytes(18) |> Base.encode64(padding: false)
    {raw, raw, nil}
  end

  defp generate_key_material(kind) when is_atom(kind), do: generate_key_material(to_string(kind))

  defp one_or_error(query) do
    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end
end
