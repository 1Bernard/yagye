defmodule YagyeCore.Providers.Schemas.MerchantProviderConnection do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_modes ~w[simulation sandbox live]
  @valid_statuses ~w[active paused disabled]

  schema "merchant_provider_connections" do
    field :mode, :string
    field :priority, :integer, default: 1
    field :enabled_methods, {:array, :string}, default: []
    field :status, :string, default: "active"

    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant
    belongs_to :provider, YagyeCore.Providers.Schemas.Provider

    timestamps(inserted_at: :inserted_at)
  end

  def changeset(conn, attrs) do
    conn
    |> cast(attrs, [:merchant_id, :provider_id, :mode, :priority, :enabled_methods, :status])
    |> validate_required([:merchant_id, :provider_id, :mode])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:priority, greater_than_or_equal_to: 1)
    |> unique_constraint([:merchant_id, :provider_id, :mode])
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:provider_id)
  end
end
