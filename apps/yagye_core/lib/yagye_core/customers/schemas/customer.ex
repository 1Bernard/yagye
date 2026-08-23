defmodule YagyeCore.Customers.Schemas.Customer do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant

  @valid_kyc_tiers ~w[tier_1 tier_2 tier_3]
  @public_id_prefix "cus_"

  @type t :: %__MODULE__{}

  schema "customers" do
    field(:public_id, :string)
    field(:merchant_customer_ref, :string)
    field(:kyc_tier, :string, default: "tier_1")
    field(:kyc_verified_at, :utc_datetime_usec)

    belongs_to(:merchant, Merchant)

    timestamps(inserted_at: :inserted_at, updated_at: :updated_at)
  end

  def create_changeset(customer, attrs) do
    customer
    |> cast(attrs, [:merchant_id, :merchant_customer_ref, :kyc_tier])
    |> validate_required([:merchant_id, :merchant_customer_ref])
    |> validate_inclusion(:kyc_tier, @valid_kyc_tiers)
    |> foreign_key_constraint(:merchant_id)
    |> unique_constraint(:public_id)
    |> unique_constraint([:merchant_id, :merchant_customer_ref])
    |> put_public_id()
  end

  def update_kyc_tier_changeset(customer, kyc_tier, verified_at \\ nil) do
    customer
    |> change(kyc_tier: kyc_tier, kyc_verified_at: verified_at || DateTime.utc_now())
    |> validate_inclusion(:kyc_tier, @valid_kyc_tiers)
  end

  defp put_public_id(%Ecto.Changeset{valid?: true} = cs) do
    put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs

  def valid_kyc_tiers, do: @valid_kyc_tiers
end
