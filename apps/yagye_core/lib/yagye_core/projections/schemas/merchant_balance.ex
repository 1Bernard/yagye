defmodule YagyeCore.Projections.Schemas.MerchantBalance do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # Composite PK: (merchant_id, currency, mode) — no surrogate key needed
  @primary_key false
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "proj_merchant_balances" do
    field :merchant_id, Ecto.UUID, primary_key: true
    field :currency, :string, primary_key: true
    field :mode, :string, primary_key: true
    field :available, :integer, default: 0
    field :pending, :integer, default: 0
    field :reserved, :integer, default: 0
    field :in_transit, :integer, default: 0
    field :lifetime_volume, :integer, default: 0
    field :last_event_id, :string
    field :last_applied_at, :utc_datetime_usec
  end

  def changeset(balance, attrs) do
    balance
    |> cast(attrs, [
      :merchant_id,
      :currency,
      :mode,
      :available,
      :pending,
      :reserved,
      :in_transit,
      :lifetime_volume,
      :last_event_id,
      :last_applied_at
    ])
    |> validate_required([:merchant_id, :currency, :mode])
  end
end
