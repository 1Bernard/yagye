defmodule YagyeCore.Pricing.Schemas.PricingRule do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Pricing.Schemas.PricingPlan

  @valid_roundings ~w[half_up bankers]

  @type t :: %__MODULE__{}

  schema "pricing_rules" do
    field(:specificity, :integer)
    field(:method, :string)
    field(:provider_code, :string)
    field(:card_brand, :string)
    field(:region, :string)
    field(:amount_min, :integer)
    field(:amount_max, :integer)
    field(:percentage_bps, :integer, default: 0)
    field(:fixed_amount, :integer, default: 0)
    field(:minimum_fee, :integer)
    field(:maximum_fee, :integer)
    field(:rounding, :string, default: "half_up")

    belongs_to(:plan, PricingPlan)

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def create_changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :plan_id,
      :method,
      :provider_code,
      :card_brand,
      :region,
      :amount_min,
      :amount_max,
      :percentage_bps,
      :fixed_amount,
      :minimum_fee,
      :maximum_fee,
      :rounding
    ])
    |> validate_required([:plan_id, :percentage_bps, :fixed_amount])
    |> validate_number(:percentage_bps, greater_than_or_equal_to: 0)
    |> validate_number(:fixed_amount, greater_than_or_equal_to: 0)
    |> validate_inclusion(:rounding, @valid_roundings)
    |> foreign_key_constraint(:plan_id)
    |> put_specificity()
  end

  defp put_specificity(%Ecto.Changeset{valid?: true} = cs) do
    method = get_field(cs, :method)
    provider_code = get_field(cs, :provider_code)
    card_brand = get_field(cs, :card_brand)
    region = get_field(cs, :region)
    amount_min = get_field(cs, :amount_min)
    amount_max = get_field(cs, :amount_max)

    specificity =
      if(method, do: 1, else: 0) +
        if(provider_code, do: 2, else: 0) +
        if(card_brand, do: 4, else: 0) +
        if(region, do: 8, else: 0) +
        if amount_min || amount_max, do: 16, else: 0

    put_change(cs, :specificity, specificity)
  end

  defp put_specificity(cs), do: cs
end
