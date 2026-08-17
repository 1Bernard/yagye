defmodule YagyeCore.Merchants.MerchantMode do
  @moduledoc false
  use YagyeCore.Schema
  import Ecto.Changeset

  # Composite primary key (merchant_id, mode) — the DB constraint owns it.
  @primary_key false
  schema "merchant_modes" do
    belongs_to :merchant, YagyeCore.Merchants.Merchant
    field :mode, Yagye.Types.YagyeMode
    field :enabled_at, :utc_datetime_usec
  end

  def changeset(mode, attrs) do
    mode
    |> cast(attrs, [:merchant_id, :mode, :enabled_at])
    |> validate_required([:merchant_id, :mode, :enabled_at])
    |> foreign_key_constraint(:merchant_id)
  end
end
