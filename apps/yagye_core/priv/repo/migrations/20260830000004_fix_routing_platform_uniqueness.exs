defmodule YagyeCore.Repo.Migrations.FixRoutingPlatformUniqueness do
  use Ecto.Migration

  def change do
    # The composite index on (scope, merchant_id, mode, priority) with NULLS DISTINCT
    # does NOT enforce "one platform rule per priority per mode" because NULL != NULL
    # in Postgres unique indexes. Replace with two partial indexes.

    drop unique_index(:routing_rules, [:scope, :merchant_id, :mode, :priority])

    # platform-scope: merchant_id IS NULL — one rule per (mode, priority)
    create unique_index(:routing_rules, [:mode, :priority],
             where: "merchant_id IS NULL AND scope = 'platform'",
             name: "routing_rules_platform_mode_priority_index"
           )

    # merchant-scope: one rule per (merchant_id, mode, priority)
    create unique_index(:routing_rules, [:merchant_id, :mode, :priority],
             where: "merchant_id IS NOT NULL AND scope = 'merchant'",
             name: "routing_rules_merchant_mode_priority_index"
           )
  end
end
