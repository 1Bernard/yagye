defmodule YagyeCore.Compliance.Schemas.ScreeningHit do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "screening_hits" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant
    field :subject_type, :string
    field :subject_id, Uniq.UUID
    field :list_type, :string
    field :list_source, :string
    field :matched_name, :string
    field :match_score, :decimal
    field :matched_attributes, {:array, :string}
    field :status, :string, default: "open"
    field :disposition_reason, :string
    field :dispositioned_by, :string
    field :dispositioned_at, :utc_datetime_usec

    timestamps()
  end

  @valid_subject_types ~w[entity director ubo]
  @valid_list_types ~w[sanctions pep adverse_media]
  @valid_statuses ~w[open false_positive true_match_cleared true_match_blocked]

  @required ~w[merchant_id subject_type subject_id list_type list_source matched_name match_score]a
  @optional ~w[matched_attributes disposition_reason dispositioned_by dispositioned_at]a

  def changeset(hit, attrs) do
    hit
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:subject_type, @valid_subject_types)
    |> validate_inclusion(:list_type, @valid_list_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:merchant_id)
  end

  def disposition_changeset(hit, attrs) do
    hit
    |> cast(attrs, [:status, :disposition_reason, :dispositioned_by, :dispositioned_at])
    |> validate_required([:status, :disposition_reason, :dispositioned_by, :dispositioned_at])
    |> validate_inclusion(:status, @valid_statuses -- ["open"])
    |> validate_no_sanctions_clearance()
  end

  defp validate_no_sanctions_clearance(changeset) do
    list_type = get_field(changeset, :list_type)
    status = get_change(changeset, :status)

    if list_type == "sanctions" and status in ["false_positive", "true_match_cleared"] do
      add_error(changeset, :status, "sanctions hits cannot be cleared — absolute bar")
    else
      changeset
    end
  end
end
