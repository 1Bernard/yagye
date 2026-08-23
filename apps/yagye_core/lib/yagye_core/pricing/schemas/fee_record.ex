defmodule YagyeCore.Pricing.Schemas.FeeRecord do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Pricing.Schemas.{PricingPlan, PricingRule}

  @valid_parties ~w[platform provider]
  @valid_fee_kinds ~w[psp_margin orchestration_fee]
  @valid_modes ~w[simulation live]

  @type t :: %__MODULE__{}

  schema "fee_records" do
    field(:source_type, :string)
    field(:source_id, :binary_id)
    field(:mode, :string)
    field(:party, :string)
    field(:fee_kind, :string)
    field(:amount, :integer)
    field(:currency, :string)
    field(:computation, :map)

    belongs_to(:merchant, Merchant)
    belongs_to(:pricing_plan, PricingPlan)
    belongs_to(:pricing_rule, PricingRule)

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def record_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :source_type,
      :source_id,
      :merchant_id,
      :mode,
      :party,
      :fee_kind,
      :amount,
      :currency,
      :pricing_plan_id,
      :pricing_rule_id,
      :computation
    ])
    |> validate_required([
      :source_type,
      :source_id,
      :merchant_id,
      :mode,
      :party,
      :fee_kind,
      :amount,
      :currency,
      :computation
    ])
    |> validate_inclusion(:party, @valid_parties)
    |> validate_inclusion(:fee_kind, @valid_fee_kinds)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_length(:currency, is: 3)
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:pricing_plan_id)
    |> foreign_key_constraint(:pricing_rule_id)
    |> unique_constraint([:source_type, :source_id, :party],
      name: :fee_records_source_type_source_id_party_index
    )
  end
end
