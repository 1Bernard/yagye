defmodule YagyeCore.Repo.Migrations.AddNetworkToRoutingRuleConditionValidFields do
  use Ecto.Migration

  def up do
    drop constraint(:routing_rule_conditions, :valid_field)

    create constraint(:routing_rule_conditions, :valid_field,
             check:
               "field IN ('method','currency','amount','amount_min','amount_max'," <>
                 "'card_brand','card_funding','country','network','risk_score'," <>
                 "'customer_dispute_count','provider_health')"
           )
  end

  def down do
    drop constraint(:routing_rule_conditions, :valid_field)

    create constraint(:routing_rule_conditions, :valid_field,
             check:
               "field IN ('method','currency','amount','amount_min','amount_max'," <>
                 "'card_brand','card_funding','country','risk_score'," <>
                 "'customer_dispute_count','provider_health')"
           )
  end
end
