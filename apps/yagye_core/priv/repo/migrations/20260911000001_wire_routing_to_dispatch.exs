defmodule YagyeCore.Repo.Migrations.WireRoutingToDispatch do
  use Ecto.Migration

  # This migration makes routing rules actually influence payment dispatch:
  #
  # 1. Links routing_rules back to the routing_configuration that compiled them,
  #    so payment_attempts can record which configuration drove the routing decision.
  #
  # 2. Adds "amount" as a valid routing condition field. The Drawflow graph editor
  #    already uses field="amount" in its examples, but the DB constraint only
  #    accepted amount_min/amount_max. Now all three are valid — amount for simple
  #    comparisons, amount_min/amount_max for range conditions (both evaluated
  #    against the payment's single amount value).

  def change do
    # 1. Add routing_configuration_id to routing_rules (nullable — rules created
    #    by ops via the API have no configuration; compiled rules will have one).
    alter table(:routing_rules) do
      add :routing_configuration_id,
          references(:routing_configurations, type: :uuid, on_delete: :nilify_all),
          null: true
    end

    create index(:routing_rules, [:routing_configuration_id])

    # 2. Drop the existing valid_field constraint and add "amount" to the allowed list.
    drop constraint(:routing_rule_conditions, :valid_field)

    create constraint(:routing_rule_conditions, :valid_field,
             check:
               "field IN ('method','currency','amount','amount_min','amount_max'," <>
                 "'card_brand','card_funding','country','risk_score'," <>
                 "'customer_dispute_count','provider_health')"
           )
  end
end
