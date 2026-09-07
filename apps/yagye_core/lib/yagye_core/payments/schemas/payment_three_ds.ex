defmodule YagyeCore.Payments.Schemas.PaymentThreeDs do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:payment_id, Uniq.UUID, autogenerate: false}
  @foreign_key_type Uniq.UUID

  @valid_flows ~w[frictionless challenge]
  @valid_statuses ~w[Y N A U R]
  @valid_versions ~w[2.1 2.2]

  schema "payment_three_ds" do
    field :version, :string
    field :flow, :string
    field :status, :string
    field :eci, :string
    field :cavv, :string
    field :ds_transaction_id, :string
    field :acs_transaction_id, :string
    field :liability_shift, :boolean
    field :exemption_applied, :string
    field :challenge_started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
  end

  @required ~w[payment_id]a

  def changeset(three_ds, attrs) do
    three_ds
    |> cast(attrs, [
      :payment_id,
      :version,
      :flow,
      :status,
      :eci,
      :cavv,
      :ds_transaction_id,
      :acs_transaction_id,
      :liability_shift,
      :exemption_applied,
      :challenge_started_at,
      :completed_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:version, @valid_versions, allow_nil: true)
    |> validate_inclusion(:flow, @valid_flows, allow_nil: true)
    |> validate_inclusion(:status, @valid_statuses, allow_nil: true)
    |> foreign_key_constraint(:payment_id)
  end
end
