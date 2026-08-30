defmodule YagyeCore.Routing.Schemas.RoutingRule do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Routing.Schemas.{RoutingRuleAction, RoutingRuleCondition}

  @valid_scopes ~w[platform merchant]
  @valid_modes ~w[simulation sandbox live]

  schema "routing_rules" do
    field :scope, :string
    field :merchant_id, Uniq.UUID
    field :mode, :string
    field :name, :string
    field :priority, :integer
    field :active, :boolean, default: true

    has_many :conditions, RoutingRuleCondition, foreign_key: :rule_id
    has_many :actions, RoutingRuleAction, foreign_key: :rule_id

    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:scope, :merchant_id, :mode, :name, :priority, :active])
    |> validate_required([:scope, :mode, :name, :priority])
    |> validate_inclusion(:scope, @valid_scopes)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_scope_merchant_id()
    |> unique_constraint([:mode, :priority],
      name: :routing_rules_platform_mode_priority_index,
      message: "a platform rule at this priority already exists for this mode"
    )
    |> unique_constraint([:merchant_id, :mode, :priority],
      name: :routing_rules_merchant_mode_priority_index,
      message: "a merchant rule at this priority already exists for this merchant and mode"
    )
    |> foreign_key_constraint(:merchant_id)
  end

  defp validate_scope_merchant_id(changeset) do
    scope = get_field(changeset, :scope)
    merchant_id = get_field(changeset, :merchant_id)

    case {scope, merchant_id} do
      {"platform", mid} when not is_nil(mid) ->
        add_error(changeset, :merchant_id, "must be nil for platform-scope rules")

      {"merchant", nil} ->
        add_error(changeset, :merchant_id, "required for merchant-scope rules")

      _ ->
        changeset
    end
  end
end
