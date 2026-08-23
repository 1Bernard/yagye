defmodule YagyeCore.Reserves.Schemas.ReserveHold do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Reserves.Schemas.MerchantReserve

  @valid_states ~w[pending released drawn]

  @type t :: %__MODULE__{}

  schema "reserve_holds" do
    field :amount, :integer
    field :currency, :string
    field :mode, :string
    field :state, :string, default: "pending"
    field :held_at, :utc_datetime_usec
    field :release_at, :utc_datetime_usec
    field :released_at, :utc_datetime_usec
    field :drawn_at, :utc_datetime_usec
    field :draw_source_id, :binary_id

    belongs_to :merchant, Merchant
    belongs_to :reserve, MerchantReserve
    belongs_to :payment, Payment

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def create_changeset(hold, attrs) do
    hold
    |> cast(attrs, [
      :merchant_id,
      :reserve_id,
      :payment_id,
      :amount,
      :currency,
      :mode,
      :held_at,
      :release_at
    ])
    |> validate_required([
      :merchant_id,
      :reserve_id,
      :payment_id,
      :amount,
      :currency,
      :mode,
      :held_at,
      :release_at
    ])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> validate_inclusion(:mode, ~w[simulation live])
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:reserve_id)
    |> foreign_key_constraint(:payment_id)
    |> unique_constraint([:payment_id, :reserve_id])
  end

  def release_changeset(hold) do
    change(hold, state: "released", released_at: DateTime.utc_now())
  end

  def draw_changeset(hold, draw_source_id) do
    change(hold, state: "drawn", drawn_at: DateTime.utc_now(), draw_source_id: draw_source_id)
  end

  def valid_states, do: @valid_states
end
