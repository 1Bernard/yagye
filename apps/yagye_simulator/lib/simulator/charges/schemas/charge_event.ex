defmodule Simulator.Charges.Schemas.ChargeEvent do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Charges.Schemas.Charge

  schema "gw_charge_events" do
    field :sequence, :integer
    field :event_type, :string
    field :from_state, :string
    field :to_state, :string
    field :payload, :map, default: %{}

    belongs_to :charge, Charge

    field :created_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:charge_id, :sequence, :event_type, :from_state, :to_state, :payload])
    |> validate_required([:charge_id, :sequence, :event_type])
    |> unique_constraint([:charge_id, :sequence])
    |> foreign_key_constraint(:charge_id)
  end
end
