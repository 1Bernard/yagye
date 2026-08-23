defmodule YagyeCore.Float.Schemas.MomoFloatBalance do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Ledger.Schemas.Account

  @type t :: %__MODULE__{}

  schema "momo_float_balances" do
    field :network, :string
    field :mode, :string
    field :balance, :integer
    field :currency, :string
    field :low_water_mark, :integer
    field :last_synced_at, :utc_datetime_usec

    belongs_to :ledger_account, Account
  end

  def upsert_changeset(balance, attrs) do
    balance
    |> cast(attrs, [
      :network,
      :mode,
      :balance,
      :currency,
      :low_water_mark,
      :ledger_account_id,
      :last_synced_at
    ])
    |> validate_required([:network, :mode, :balance, :currency, :low_water_mark, :last_synced_at])
    |> validate_inclusion(:mode, ~w[simulation live])
    |> validate_length(:currency, is: 3)
    |> unique_constraint([:network, :mode])
  end

  def below_low_water?(%__MODULE__{balance: balance, low_water_mark: mark}),
    do: balance < mark
end
