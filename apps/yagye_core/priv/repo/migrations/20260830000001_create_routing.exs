defmodule YagyeCore.Repo.Migrations.CreateRouting do
  use Ecto.Migration

  def change do
    # ── routing_rules ──────────────────────────────────────────────────────────
    # Routing rules define which payment provider to use for a given payment.
    # Platform-scope rules (merchant_id IS NULL) are Yagye ops-managed.
    # Merchant-scope rules (merchant_id IS NOT NULL) are enterprise overrides.
    create table(:routing_rules, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # platform|merchant
      add :scope, :text, null: false
      # NULL for platform-scope; set for enterprise overrides only
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all)
      add :mode, :text, null: false
      add :name, :text, null: false
      # lower wins within scope; merchant rules always evaluated first
      add :priority, :integer, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec, inserted_at: :inserted_at)
    end

    create constraint(:routing_rules, :valid_scope, check: "scope IN ('platform','merchant')")

    create constraint(:routing_rules, :valid_mode,
             check: "mode IN ('simulation','sandbox','live')"
           )

    create constraint(:routing_rules, :merchant_scope_requires_merchant_id,
             check:
               "(scope = 'platform' AND merchant_id IS NULL) OR (scope = 'merchant' AND merchant_id IS NOT NULL)"
           )

    # NULLS DISTINCT (Postgres default) keeps platform and merchant namespaces separate
    create unique_index(:routing_rules, [:scope, :merchant_id, :mode, :priority],
             nulls_distinct: true
           )

    # ── routing_rule_conditions ────────────────────────────────────────────────
    # AND-semantics: every condition in a rule must match.
    create table(:routing_rule_conditions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :rule_id, references(:routing_rules, type: :uuid, on_delete: :delete_all), null: false

      # method|currency|amount_min|amount_max|card_brand|card_funding|country|risk_score|customer_dispute_count|provider_health
      add :field, :text, null: false
      # eq|neq|gt|gte|lt|lte|in|not_in
      add :operator, :text, null: false
      # scalar or array value; jsonb supports heterogeneous types without schema explosion
      add :value, :map, null: false
      # display order; AND semantics, not OR
      add :position, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false, inserted_at: :inserted_at)
    end

    valid_fields =
      ~w[method currency amount_min amount_max card_brand card_funding country risk_score customer_dispute_count provider_health]

    valid_operators = ~w[eq neq gt gte lt lte in not_in]

    create constraint(:routing_rule_conditions, :valid_field,
             check: "field IN (#{Enum.map_join(valid_fields, ",", &"'#{&1}'")})"
           )

    create constraint(:routing_rule_conditions, :valid_operator,
             check: "operator IN (#{Enum.map_join(valid_operators, ",", &"'#{&1}'")})"
           )

    create unique_index(:routing_rule_conditions, [:rule_id, :position])

    # ── routing_rule_actions ───────────────────────────────────────────────────
    # Each rule names one or more providers in fallback priority order.
    # ALL named providers must be degraded before the rule fails — no cross-rule fallback.
    create table(:routing_rule_actions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :rule_id, references(:routing_rules, type: :uuid, on_delete: :delete_all), null: false
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict), null: false
      # within-rule fallback ordering
      add :priority, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false, inserted_at: :inserted_at)
    end

    create unique_index(:routing_rule_actions, [:rule_id, :priority])
    create index(:routing_rule_actions, [:provider_id])
  end
end
