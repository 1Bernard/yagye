defmodule YagyeCore.Ledger.Schemas.Entry do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_modes ~w[simulation sandbox live]

  schema "ledger_entries" do
    field :public_id, :string
    field :mode, :string
    field :currency, :string
    field :entry_type, :string
    field :source_type, :string
    field :source_id, Ecto.UUID
    field :description, :string
    field :correlation_id, :string
    field :reverses_entry_id, Ecto.UUID
    field :effective_at, :utc_datetime_usec
    field :recorded_at, :utc_datetime_usec

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :public_id,
      :mode,
      :currency,
      :entry_type,
      :source_type,
      :source_id,
      :description,
      :correlation_id,
      :reverses_entry_id,
      :effective_at,
      :recorded_at
    ])
    |> validate_required([
      :mode,
      :currency,
      :entry_type,
      :source_type,
      :source_id,
      :description,
      :correlation_id,
      :effective_at,
      :recorded_at
    ])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_length(:currency, is: 3)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> unique_constraint([:source_type, :source_id, :entry_type])
  end

  defp put_public_id(%{data: %{public_id: nil}} = changeset) do
    put_change(changeset, :public_id, "led_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(changeset), do: changeset
end
