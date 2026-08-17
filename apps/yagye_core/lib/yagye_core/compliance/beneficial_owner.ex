defmodule YagyeCore.Compliance.BeneficialOwner do
  @moduledoc false
  use YagyeCore.Schema
  import Ecto.Changeset

  schema "beneficial_owners" do
    belongs_to :merchant, YagyeCore.Merchants.Merchant
    # subject_ref points to pii_vault — personal data lives there, not here.
    field :subject_ref, Uniq.UUID
    field :ownership_bps, :integer
    field :role, :string

    timestamps(updated_at: false)
  end

  @valid_roles ~w[director ubo both]

  def changeset(owner, attrs) do
    owner
    |> cast(attrs, [:merchant_id, :subject_ref, :ownership_bps, :role])
    |> validate_required([:merchant_id, :subject_ref, :role])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_number(:ownership_bps, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> foreign_key_constraint(:merchant_id)
  end
end
