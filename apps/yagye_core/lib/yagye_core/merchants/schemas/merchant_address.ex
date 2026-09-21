defmodule YagyeCore.Merchants.Schemas.MerchantAddress do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "merchant_addresses" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant

    field :country, :string
    field :region, :string
    field :city, :string
    field :street_address, :string
    field :gps_address, :string
    field :complex_building, :string
    field :address_type, :string, default: "office"

    timestamps()
  end

  @valid_address_types ~w[registered office]

  @optional ~w[country region city street_address gps_address complex_building]a

  def changeset(address, attrs) do
    address
    |> cast(attrs, [:merchant_id, :address_type | @optional])
    |> validate_required([:merchant_id, :address_type])
    |> validate_inclusion(:address_type, @valid_address_types)
    |> validate_length(:country, is: 2)
    |> unique_constraint([:merchant_id, :address_type])
    |> foreign_key_constraint(:merchant_id)
  end
end
