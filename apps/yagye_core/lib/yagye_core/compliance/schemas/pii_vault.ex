defmodule YagyeCore.Compliance.Schemas.PiiVault do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  # subject_ref is the PK — destroying this record's KMS key crypto-shreds
  # every copy of this subject's personal data across all immutable stores.
  @primary_key {:subject_ref, Uniq.UUID, version: 7, autogenerate: true}
  schema "pii_vault" do
    field :kms_key_id, :string
    field :ciphertext, :binary
    field :subject_kind, :string
    field :erased_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end

  @valid_kinds ~w[customer beneficial_owner merchant_user]

  @required ~w[kms_key_id ciphertext subject_kind]a

  def changeset(vault, attrs) do
    vault
    |> cast(attrs, @required ++ [:erased_at])
    |> validate_required(@required)
    |> validate_inclusion(:subject_kind, @valid_kinds)
  end
end
