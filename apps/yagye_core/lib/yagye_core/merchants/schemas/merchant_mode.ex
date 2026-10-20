defmodule YagyeCore.Merchants.Schemas.MerchantMode do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  # Composite primary key (merchant_id, mode) — the DB constraint owns it.
  @primary_key false
  schema "merchant_modes" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant
    field :mode, YagyeCore.Shared.Types.YagyeMode
    field :enabled_at, :utc_datetime_usec
  end

  def changeset(mode, attrs) do
    mode
    |> cast(attrs, [:mode, :enabled_at])
    |> put_change(:merchant_id, attrs[:merchant_id])
    |> validate_required([:merchant_id, :mode, :enabled_at])
    |> foreign_key_constraint(:merchant_id)
  end
end
