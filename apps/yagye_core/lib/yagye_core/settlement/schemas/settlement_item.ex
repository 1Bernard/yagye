defmodule YagyeCore.Settlement.Schemas.SettlementItem do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Settlement.Schemas.Settlement

  @valid_source_types ~w[payment_attempt payment_capture refund chargeback adjustment fee]

  @type t :: %__MODULE__{}

  schema "settlement_items" do
    field :source_type, :string
    field :source_id, :binary_id
    field :gross_amount, :integer
    field :provider_fee, :integer, default: 0
    field :platform_fee, :integer, default: 0
    field :net_amount, :integer
    field :currency, :string
    field :fx_rate, :decimal
    field :fx_source, :string
    field :fx_quoted_at, :utc_datetime_usec

    belongs_to :settlement, Settlement

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :settlement_id,
      :source_type,
      :source_id,
      :gross_amount,
      :provider_fee,
      :platform_fee,
      :net_amount,
      :currency,
      :fx_rate,
      :fx_source,
      :fx_quoted_at
    ])
    |> validate_required([
      :settlement_id,
      :source_type,
      :source_id,
      :gross_amount,
      :net_amount,
      :currency
    ])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_length(:currency, is: 3)
    |> validate_number(:gross_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:settlement_id)
    |> unique_constraint([:settlement_id, :source_type, :source_id])
  end
end
