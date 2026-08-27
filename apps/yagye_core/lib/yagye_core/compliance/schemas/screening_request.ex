defmodule YagyeCore.Compliance.Schemas.ScreeningRequest do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "screening_requests" do
    belongs_to :subject, YagyeCore.Compliance.Schemas.ScreeningSubject
    field :provider_code, :string
    field :trigger, :string
    field :lists_checked, {:array, :string}
    field :search_ref, :string
    field :status, :string, default: "pending"
    field :match_count, :integer
    field :hit_count, :integer
    field :raw_response, :map
    field :error, :string
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @valid_triggers ~w[onboarding periodic manual transaction_threshold]
  @valid_statuses ~w[pending completed failed timed_out]

  @required ~w[subject_id provider_code trigger lists_checked]a
  @optional ~w[search_ref status match_count hit_count raw_response error completed_at]a

  def changeset(request, attrs) do
    request
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:trigger, @valid_triggers)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:subject_id)
  end

  def complete_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :status,
      :search_ref,
      :match_count,
      :hit_count,
      :raw_response,
      :completed_at,
      :error
    ])
    |> validate_inclusion(:status, @valid_statuses -- ["pending"])
  end
end
