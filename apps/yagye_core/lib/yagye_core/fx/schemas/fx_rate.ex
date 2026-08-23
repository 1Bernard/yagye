defmodule YagyeCore.Fx.Schemas.FxRate do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "fx_rates" do
    field :base, :string
    field :quote, :string
    field :rate, :decimal
    field :source, :string
    field :markup_bps, :integer
    field :quoted_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def create_changeset(fx_rate, attrs) do
    fx_rate
    |> cast(attrs, [:base, :quote, :rate, :source, :markup_bps, :quoted_at, :expires_at])
    |> validate_required([:base, :quote, :rate, :source, :markup_bps, :quoted_at, :expires_at])
    |> validate_length(:base, is: 3)
    |> validate_length(:quote, is: 3)
    |> validate_number(:markup_bps, greater_than_or_equal_to: 0)
  end
end
