defmodule YagyeCore.Projections.Schemas.DailyMetrics do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # Composite PK: (merchant_id, day, currency, mode)
  @primary_key false
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "proj_daily_merchant_metrics" do
    field :merchant_id, Ecto.UUID, primary_key: true
    field :day, :date, primary_key: true
    field :currency, :string, primary_key: true
    field :mode, :string, primary_key: true
    field :payment_count, :integer, default: 0
    field :succeeded_count, :integer, default: 0
    field :failed_count, :integer, default: 0
    field :gross_volume, :integer, default: 0
    field :net_volume, :integer, default: 0
    field :refund_volume, :integer, default: 0
    field :chargeback_count, :integer, default: 0
  end

  def changeset(metrics, attrs) do
    metrics
    |> cast(attrs, [
      :merchant_id,
      :day,
      :currency,
      :mode,
      :payment_count,
      :succeeded_count,
      :failed_count,
      :gross_volume,
      :net_volume,
      :refund_volume,
      :chargeback_count
    ])
    |> validate_required([:merchant_id, :day, :currency, :mode])
  end
end
