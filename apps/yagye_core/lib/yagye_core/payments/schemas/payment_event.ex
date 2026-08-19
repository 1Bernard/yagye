defmodule YagyeCore.Payments.Schemas.PaymentEvent do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "payment_events" do
    field :version,        :integer
    field :event_type,     :string
    field :from_state,     :string
    field :to_state,       :string
    field :payload,        :map,    default: %{}
    field :actor,          :string
    field :correlation_id, :string
    field :occurred_at,    :utc_datetime_usec
    field :recorded_at,    :utc_datetime_usec

    belongs_to :payment, YagyeCore.Payments.Schemas.Payment
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:payment_id, :version, :event_type, :from_state, :to_state,
                    :payload, :actor, :correlation_id, :occurred_at, :recorded_at])
    |> validate_required([:payment_id, :version, :event_type, :actor, :correlation_id,
                          :occurred_at, :recorded_at])
    |> unique_constraint([:payment_id, :version])
    |> foreign_key_constraint(:payment_id)
  end
end
