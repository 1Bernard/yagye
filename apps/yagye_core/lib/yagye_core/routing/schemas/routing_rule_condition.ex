defmodule YagyeCore.Routing.Schemas.RoutingRuleCondition do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_fields ~w[method currency amount_min amount_max card_brand card_funding country
                   risk_score customer_dispute_count provider_health]
  @valid_operators ~w[eq neq gt gte lt lte in not_in]

  schema "routing_rule_conditions" do
    field :rule_id, Uniq.UUID
    field :field, :string
    field :operator, :string
    field :value, :map
    field :position, :integer

    timestamps(updated_at: false)
  end

  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [:rule_id, :field, :operator, :value, :position])
    |> validate_required([:rule_id, :field, :operator, :value, :position])
    |> validate_inclusion(:field, @valid_fields)
    |> validate_inclusion(:operator, @valid_operators)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:rule_id, :position])
    |> foreign_key_constraint(:rule_id)
  end
end
