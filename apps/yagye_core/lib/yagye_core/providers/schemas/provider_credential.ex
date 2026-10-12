defmodule YagyeCore.Providers.Schemas.ProviderCredential do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_modes ~w[simulation sandbox live]

  schema "provider_credentials" do
    field :mode, :string
    field :base_url, :string
    # Mutually exclusive credential sources:
    # encrypted_payload — AES-256-GCM blob via Vault (Simulator, fallback)
    # secret_name       — AWS Secrets Manager secret name (external PSPs, production)
    field :encrypted_payload, :binary
    field :secret_name, :string
    field :active, :boolean, default: true

    belongs_to :provider, YagyeCore.Providers.Schemas.Provider
    # NULL for platform-level credentials
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant

    timestamps(inserted_at: :inserted_at)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :provider_id,
      :merchant_id,
      :mode,
      :base_url,
      :encrypted_payload,
      :secret_name,
      :active
    ])
    |> validate_required([:provider_id, :mode, :base_url])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_credential_source()
    |> unique_constraint([:provider_id, :merchant_id, :mode])
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:merchant_id)
  end

  defp validate_credential_source(changeset) do
    secret_name = get_field(changeset, :secret_name)
    encrypted_payload = get_field(changeset, :encrypted_payload)

    if is_nil(secret_name) and is_nil(encrypted_payload) do
      add_error(changeset, :encrypted_payload, "must be set when secret_name is not provided")
    else
      changeset
    end
  end
end
