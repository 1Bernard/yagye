defmodule YagyeCore.Idempotency.Schemas.IdempotencyKey do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "idempotency_keys" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant
    field :key, :string
    field :request_fingerprint, :string
    field :command_name, :string
    field :state, :string, default: "in_progress"
    field :lease_expires_at, :utc_datetime_usec
    field :response_status, :integer
    field :response_body, :map
    field :resource_type, :string
    field :resource_id, Uniq.UUID
    field :executed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps()
  end

  @valid_states ~w[in_progress completed failed]

  @required ~w[merchant_id key request_fingerprint expires_at]a
  @optional ~w[command_name lease_expires_at response_status response_body resource_type resource_id executed_at]a

  def changeset(idem_key, attrs) do
    idem_key
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:key, max: 255)
    |> unique_constraint([:merchant_id, :key])
    |> foreign_key_constraint(:merchant_id)
  end

  def complete_changeset(idem_key, attrs) do
    idem_key
    |> cast(attrs, [
      :state,
      :response_status,
      :response_body,
      :resource_type,
      :resource_id,
      :executed_at
    ])
    |> validate_required([:state, :response_status, :executed_at])
    |> validate_inclusion(:state, @valid_states -- ["in_progress"])
  end
end
