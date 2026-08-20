defmodule YagyeCore.Providers.Schemas.ProviderCredential do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_modes ~w[simulation sandbox live]

  schema "provider_credentials" do
    field :mode, :string
    field :base_url, :string
    field :encrypted_payload, :binary
    field :active, :boolean, default: true

    belongs_to :provider, YagyeCore.Providers.Schemas.Provider
    # NULL for platform-level credentials
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant

    timestamps(inserted_at: :inserted_at)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:provider_id, :merchant_id, :mode, :base_url, :encrypted_payload, :active])
    |> validate_required([:provider_id, :mode, :base_url, :encrypted_payload])
    |> validate_inclusion(:mode, @valid_modes)
    |> unique_constraint([:provider_id, :merchant_id, :mode])
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:merchant_id)
  end
end
