defmodule YagyeCore.Checkout.Schemas.CheckoutEvent do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_event_types ~w[viewed method_selected submitted validation_failed
                        redirected_3ds returned abandoned]

  # Append-only telemetry — no updated_at, no standard timestamps()
  schema "checkout_events" do
    field :session_id, Uniq.UUID
    field :event_type, :string
    field :method_selected, :string
    field :payload, :map, default: %{}
    field :ip_hash, :string
    field :user_agent_hash, :string
    field :occurred_at, :utc_datetime_usec
  end

  @required ~w[session_id event_type occurred_at]a

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :session_id,
      :event_type,
      :method_selected,
      :payload,
      :ip_hash,
      :user_agent_hash,
      :occurred_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:event_type, @valid_event_types)
    |> foreign_key_constraint(:session_id)
  end
end
