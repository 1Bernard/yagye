defmodule YagyeCore.Outbox.Schemas.OutboxMessage do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # bigserial pk — DB assigns it; autogenerate: true triggers RETURNING so the
  # inserted struct carries the DB-assigned id immediately after Repo.insert
  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  @valid_destinations ~w[internal:projections kafka:payments kafka:merchants kafka:disputes]

  schema "outbox_messages" do
    field :event_id, :string
    field :aggregate_type, :string
    field :aggregate_id, Ecto.UUID
    field :aggregate_version, :integer
    field :event_type, :string
    field :event_version, :integer
    field :partition_key, :string
    field :merchant_id, Ecto.UUID
    field :destination, :string
    field :envelope, :map
    field :mode, :string
    field :published_at, :utc_datetime_usec
    field :publish_attempts, :integer, default: 0
    field :last_error, :string
    field :occurred_at, :utc_datetime_usec

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [
      :event_id,
      :aggregate_type,
      :aggregate_id,
      :aggregate_version,
      :event_type,
      :event_version,
      :partition_key,
      :merchant_id,
      :destination,
      :envelope,
      :mode,
      :occurred_at
    ])
    |> validate_required([
      :event_id,
      :aggregate_type,
      :aggregate_id,
      :aggregate_version,
      :event_type,
      :event_version,
      :partition_key,
      :destination,
      :envelope,
      :mode,
      :occurred_at
    ])
    |> validate_inclusion(:destination, @valid_destinations)
    |> unique_constraint(:event_id)
  end

  def mark_published_changeset(msg) do
    change(msg, published_at: DateTime.utc_now(), publish_attempts: msg.publish_attempts + 1)
  end

  def mark_failed_changeset(msg, reason) do
    change(msg,
      publish_attempts: msg.publish_attempts + 1,
      last_error: inspect(reason)
    )
  end
end
