defmodule YagyeCore.Repo.Migrations.RoutingRulesUniqueActiveOnly do
  use Ecto.Migration

  # The previous indexes enforced uniqueness across ALL rules (active and inactive),
  # which blocks re-publishing a configuration at the same priority slot after the
  # previous config's rules are deactivated.
  # Fix: add `AND active = true` so only live rules compete for a slot.

  def up do
    drop index(:routing_rules, [:mode, :priority],
           where: "merchant_id IS NULL AND scope = 'platform'",
           name: "routing_rules_platform_mode_priority_index"
         )

    drop index(:routing_rules, [:merchant_id, :mode, :priority],
           where: "merchant_id IS NOT NULL AND scope = 'merchant'",
           name: "routing_rules_merchant_mode_priority_index"
         )

    create unique_index(:routing_rules, [:mode, :priority],
             where: "merchant_id IS NULL AND scope = 'platform' AND active = true",
             name: "routing_rules_platform_mode_priority_index"
           )

    create unique_index(:routing_rules, [:merchant_id, :mode, :priority],
             where: "merchant_id IS NOT NULL AND scope = 'merchant' AND active = true",
             name: "routing_rules_merchant_mode_priority_index"
           )
  end

  def down do
    drop index(:routing_rules, [:mode, :priority],
           where: "merchant_id IS NULL AND scope = 'platform' AND active = true",
           name: "routing_rules_platform_mode_priority_index"
         )

    drop index(:routing_rules, [:merchant_id, :mode, :priority],
           where: "merchant_id IS NOT NULL AND scope = 'merchant' AND active = true",
           name: "routing_rules_merchant_mode_priority_index"
         )

    create unique_index(:routing_rules, [:mode, :priority],
             where: "merchant_id IS NULL AND scope = 'platform'",
             name: "routing_rules_platform_mode_priority_index"
           )

    create unique_index(:routing_rules, [:merchant_id, :mode, :priority],
             where: "merchant_id IS NOT NULL AND scope = 'merchant'",
             name: "routing_rules_merchant_mode_priority_index"
           )
  end
end
