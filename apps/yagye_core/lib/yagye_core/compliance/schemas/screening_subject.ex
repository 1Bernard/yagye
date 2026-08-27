defmodule YagyeCore.Compliance.Schemas.ScreeningSubject do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "screening_subjects" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant
    field :subject_type, :string
    field :subject_id, Uniq.UUID
    field :screening_status, :string, default: "pending"
    field :enrolled_at, :utc_datetime_usec
    field :last_screened_at, :utc_datetime_usec
    field :next_screening_at, :utc_datetime_usec
    field :screening_frequency_days, :integer, default: 365
    field :risk_override, :string

    timestamps(type: :utc_datetime_usec)
  end

  @valid_subject_types ~w[entity beneficial_owner director customer]
  @valid_statuses ~w[pending clean potential_match confirmed_pep confirmed_match_blocked cleared suspended]

  @required ~w[merchant_id subject_type subject_id enrolled_at]a
  @optional ~w[screening_status screening_frequency_days last_screened_at next_screening_at risk_override]a

  def changeset(subject, attrs) do
    subject
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:subject_type, @valid_subject_types)
    |> validate_inclusion(:screening_status, @valid_statuses)
    |> validate_number(:screening_frequency_days, greater_than: 0)
    |> foreign_key_constraint(:merchant_id)
    |> unique_constraint([:subject_type, :subject_id])
  end

  def update_changeset(subject, attrs) do
    subject
    |> cast(attrs, [
      :screening_status,
      :last_screened_at,
      :next_screening_at,
      :screening_frequency_days,
      :risk_override
    ])
    |> validate_inclusion(:screening_status, @valid_statuses)
  end
end
