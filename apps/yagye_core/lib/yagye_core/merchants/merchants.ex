defmodule YagyeCore.Merchants do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi

  alias YagyeCore.Merchants.Commands.{
    ApproveMerchant,
    IssueApiKey,
    RegisterMerchant,
    RevokeApiKey,
    StartKybReview,
    SubmitBasicInfo,
    SubmitKybDocuments
  }

  alias YagyeCore.Merchants.Events.{
    ApiKeyIssued,
    ApiKeyRevoked,
    KybBasicInfoSubmitted,
    KybDocumentsSubmitted,
    KybReviewStarted,
    MerchantApproved,
    MerchantRegistered
  }

  alias YagyeCore.Compliance
  alias YagyeCore.Merchants.Schemas.{ApiKey, Merchant, MerchantMode}
  alias YagyeCore.Outbox
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

  # State-only transition for ops tooling. Business metadata is stored via Compliance.submit_onboarding/2.
  def submit_basic_info(merchant_id, submitted_by) do
    dispatch(%SubmitBasicInfo{merchant_id: merchant_id, submitted_by: submitted_by})
  end

  def submit_documents(merchant_id, submitted_by) do
    dispatch(%SubmitKybDocuments{merchant_id: merchant_id, submitted_by: submitted_by})
  end

  def start_review(merchant_id, reviewed_by) do
    dispatch(%StartKybReview{merchant_id: merchant_id, reviewed_by: reviewed_by})
  end

  def approve(merchant_id, approved_by) do
    dispatch(%ApproveMerchant{merchant_id: merchant_id, approved_by: approved_by})
  end

  def check_live_capable?(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
      %Merchant{kyb_tier: tier} when tier >= 3 -> :ok
      %Merchant{} -> {:error, :kyb_required}
      nil -> {:error, :not_found}
    end
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

  def get_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  def list_merchants(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    merchants =
      from(m in Merchant,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {:ok, merchants}
  end

  def list_api_keys(merchant_id) do
    keys =
      from(k in ApiKey,
        where: k.merchant_id == ^merchant_id and is_nil(k.revoked_at),
        order_by: [desc: k.inserted_at]
      )
      |> Repo.all()

    {:ok, keys}
  end

  def live_mode_enabled?(merchant_id) do
    Repo.exists?(
      from m in MerchantMode,
        where: m.merchant_id == ^merchant_id and m.mode == :live
    )
  end

  # ── Dispatch ─────────────────────────────────────────────────────────────────

  defp dispatch(%RegisterMerchant{} = cmd) do
    attrs = %{
      public_id: "mch_#{Uniq.UUID.uuid7()}",
      legal_name: cmd.legal_name,
      trading_name: cmd.trading_name,
      country: cmd.country && String.upcase(cmd.country),
      default_currency: cmd.default_currency && String.upcase(cmd.default_currency),
      api_version: "2026-01-01",
      metadata: cmd.metadata || %{}
    }

    Multi.new()
    |> Multi.insert(:merchant, Merchant.changeset(%Merchant{}, attrs))
    |> Multi.run(:mode, fn _repo, %{merchant: merchant} ->
      grant_mode(merchant.id, :simulation)
    end)
    |> Multi.insert(:outbox, fn %{merchant: merchant} ->
      Outbox.build_changeset(merchant, "merchant.registered", %{
        legal_name: merchant.legal_name,
        trading_name: merchant.trading_name,
        country: merchant.country,
        default_currency: merchant.default_currency
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{merchant: merchant}} ->
        event = %MerchantRegistered{
          merchant_id: merchant.id,
          public_id: merchant.public_id,
          legal_name: merchant.legal_name,
          trading_name: merchant.trading_name,
          country: merchant.country,
          default_currency: merchant.default_currency,
          occurred_at: DateTime.utc_now()
        }

        {:ok, {merchant, event}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp dispatch(%SubmitBasicInfo{} = cmd) do
    transition(:basic_info_submitted, cmd.merchant_id, fn merchant ->
      Merchant.onboarding_changeset(merchant, %{
        onboarding_state: "basic_info_submitted",
        kyb_tier: 1
      })
    end)
    |> case do
      {:ok, merchant} ->
        event = %KybBasicInfoSubmitted{
          merchant_id: merchant.id,
          submitted_by: cmd.submitted_by,
          occurred_at: DateTime.utc_now()
        }

        {:ok, {merchant, event}}

      error ->
        error
    end
  end

  defp dispatch(%SubmitKybDocuments{} = cmd) do
    transition(:documents_submitted, cmd.merchant_id, fn merchant ->
      Merchant.onboarding_changeset(merchant, %{
        onboarding_state: "documents_submitted",
        kyb_tier: 2
      })
    end)
    |> case do
      {:ok, merchant} ->
        event = %KybDocumentsSubmitted{
          merchant_id: merchant.id,
          submitted_by: cmd.submitted_by,
          occurred_at: DateTime.utc_now()
        }

        {:ok, {merchant, event}}

      error ->
        error
    end
  end

  defp dispatch(%StartKybReview{} = cmd) do
    transition(:under_review, cmd.merchant_id, fn merchant ->
      Merchant.onboarding_changeset(merchant, %{
        onboarding_state: "under_review",
        reviewed_by: cmd.reviewed_by
      })
    end)
    |> case do
      {:ok, merchant} ->
        event = %KybReviewStarted{
          merchant_id: merchant.id,
          reviewed_by: cmd.reviewed_by,
          occurred_at: DateTime.utc_now()
        }

        {:ok, {merchant, event}}

      error ->
        error
    end
  end

  defp dispatch(%ApproveMerchant{} = cmd) do
    Multi.new()
    |> Multi.run(:merchant, fn _repo, _changes ->
      fetch_approvable(cmd.merchant_id)
    end)
    |> Multi.run(:threshold_check, fn _repo, %{merchant: merchant} ->
      if Compliance.ubo_threshold_cleared?(merchant.id) do
        {:ok, :cleared}
      else
        {:error, :unscreened_ubos}
      end
    end)
    |> Multi.update(:approved, fn %{merchant: merchant} ->
      Merchant.onboarding_changeset(merchant, %{
        status: "approved",
        onboarding_state: "approved",
        kyb_tier: 3,
        approved_by: cmd.approved_by
      })
    end)
    |> Multi.run(:mode, fn _repo, %{approved: merchant} ->
      grant_mode(merchant.id, :live)
    end)
    |> Multi.insert(:outbox, fn %{approved: merchant} ->
      Outbox.build_changeset(merchant, "merchant.approved", %{
        approved_by: cmd.approved_by
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{approved: merchant}} ->
        event = %MerchantApproved{
          merchant_id: merchant.id,
          approved_by: cmd.approved_by,
          occurred_at: DateTime.utc_now()
        }

        {:ok, {merchant, event}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp dispatch(%IssueApiKey{} = cmd) do
    {raw_key, key_prefix, secret_hash} = generate_key_material(cmd.kind)

    Multi.new()
    |> Multi.run(:merchant, fn _repo, _changes ->
      resolve_merchant(cmd.merchant_id)
    end)
    |> Multi.insert(:api_key, fn %{merchant: merchant} ->
      attrs = %{
        public_id: "key_#{Uniq.UUID.uuid7()}",
        merchant_id: merchant.id,
        mode: cmd.mode,
        kind: to_string(cmd.kind),
        key_prefix: key_prefix,
        secret_hash: secret_hash,
        scopes: cmd.scopes,
        expires_at: cmd.expires_at,
        created_by: cmd.created_by
      }

      ApiKey.changeset(%ApiKey{}, attrs)
    end)
    |> Multi.insert(:outbox, fn %{api_key: api_key} ->
      Outbox.build_changeset(api_key, "merchant.api_key_issued", %{
        merchant_id: api_key.merchant_id,
        mode: api_key.mode,
        kind: api_key.kind,
        scopes: api_key.scopes
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{api_key: api_key}} ->
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

        # raw_key is returned here and ONLY here — never stored, never logged
        {:ok, {api_key, raw_key, event}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp dispatch(%RevokeApiKey{} = cmd) do
    Multi.new()
    |> Multi.run(:merchant, fn _repo, _changes ->
      resolve_merchant(cmd.merchant_id)
    end)
    |> Multi.run(:api_key, fn _repo, %{merchant: merchant} ->
      query =
        from(k in ApiKey,
          where: k.public_id == ^cmd.api_key_id,
          where: k.merchant_id == ^merchant.id,
          where: is_nil(k.revoked_at)
        )

      one_or_error(query)
    end)
    |> Multi.update(:revoked, fn %{api_key: api_key} ->
      Ecto.Changeset.change(api_key, revoked_at: DateTime.utc_now())
    end)
    |> Multi.insert(:outbox, fn %{revoked: api_key} ->
      Outbox.build_changeset(api_key, "merchant.api_key_revoked", %{
        merchant_id: api_key.merchant_id,
        revoked_by: cmd.revoked_by
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{revoked: api_key}} ->
        event = %ApiKeyRevoked{
          api_key_id: api_key.id,
          merchant_id: api_key.merchant_id,
          revoked_by: cmd.revoked_by,
          occurred_at: DateTime.utc_now()
        }

        {:ok, {api_key, event}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
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

  defp fetch_approvable(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      %Merchant{status: "registered", onboarding_state: "under_review"} = m -> {:ok, m}
      %Merchant{status: "approved"} -> {:error, :invalid_state}
      %Merchant{} -> {:error, :not_kyb_ready}
      nil -> {:error, :not_found}
    end
  end

  @onboarding_predecessors %{
    "basic_info_submitted" => "registered",
    "documents_submitted" => "basic_info_submitted",
    "under_review" => "documents_submitted"
  }

  defp transition(name, public_id, changeset_fn) do
    expected_predecessor = @onboarding_predecessors[to_string(name)]

    case Repo.get_by(Merchant, public_id: public_id) do
      %Merchant{onboarding_state: ^expected_predecessor} = merchant ->
        merchant |> changeset_fn.() |> Repo.update()

      %Merchant{} ->
        {:error, :invalid_state}

      nil ->
        {:error, :not_found}
    end
  end

  defp resolve_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
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
