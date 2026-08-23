defmodule YagyeCore.Webhooks.Schemas.WebhookEvent do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_states ~w[pending processed failed]

  schema "webhook_events" do
    field :provider_code, :string
    field :event_id, :string
    field :event_type, :string
    field :raw_body, :string
    field :headers, :map, default: %{}
    field :state, :string, default: "pending"
    field :error, :string
    field :processed_at, :utc_datetime_usec

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :provider_code,
      :event_id,
      :event_type,
      :raw_body,
      :headers,
      :state,
      :error,
      :processed_at
    ])
    |> validate_required([:provider_code, :event_id, :event_type, :raw_body])
    |> validate_inclusion(:state, @valid_states)
    |> unique_constraint([:provider_code, :event_id],
      name: :webhook_events_provider_code_event_id_index
    )
  end
end
