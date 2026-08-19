defmodule YagyeCore.Compliance.Schemas.KybDocument do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "kyb_documents" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant
    field :kind, :string
    field :s3_key, :string
    field :checksum, :string
    field :scanned_at, :utc_datetime_usec
    field :uploaded_by, :string

    timestamps(updated_at: false)
  end

  @valid_kinds ~w[incorporation id proof_of_address bank_confirmation]

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:merchant_id, :kind, :s3_key, :checksum, :uploaded_by, :scanned_at])
    |> validate_required([:merchant_id, :kind, :s3_key, :checksum, :uploaded_by])
    |> validate_inclusion(:kind, @valid_kinds)
    |> foreign_key_constraint(:merchant_id)
  end
end
