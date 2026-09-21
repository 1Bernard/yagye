defmodule YagyeCore.Compliance.Schemas.KybDocument do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "kyb_documents" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant
    field :kind, :string
    field :label, :string
    field :status, :string, default: "pending_upload"
    field :required_for_business_types, {:array, :string}, default: []
    field :s3_key, :string
    field :checksum, :string
    field :scanned_at, :utc_datetime_usec
    field :uploaded_by, :string
    field :reviewer_notes, :string
    field :reviewed_by, :string
    field :reviewed_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end

  @valid_kinds ~w[incorporation id proof_of_address bank_confirmation
                  form_a certificate_of_incorporation business_registration
                  tax_clearance utility_bill bank_statement]

  @valid_statuses ~w[pending_upload uploaded under_review approved rejected]

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [
      :merchant_id,
      :kind,
      :label,
      :status,
      :required_for_business_types,
      :s3_key,
      :checksum,
      :uploaded_by,
      :scanned_at
    ])
    |> validate_required([:merchant_id, :kind, :uploaded_by])
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:merchant_id)
  end

  def upload_changeset(doc, attrs) do
    doc
    |> cast(attrs, [:s3_key, :checksum, :scanned_at, :status])
    |> validate_required([:s3_key, :checksum])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def review_changeset(doc, attrs) do
    doc
    |> cast(attrs, [:status, :reviewer_notes, :reviewed_by, :reviewed_at])
    |> validate_required([:status, :reviewed_by, :reviewed_at])
    |> validate_review_status()
  end

  defp validate_review_status(changeset) do
    case get_field(changeset, :status) do
      s when s in ~w[approved rejected] -> changeset
      _ -> add_error(changeset, :status, "is invalid")
    end
  end
end
