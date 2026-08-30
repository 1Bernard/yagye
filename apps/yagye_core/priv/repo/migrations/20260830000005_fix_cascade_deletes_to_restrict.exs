defmodule YagyeCore.Repo.Migrations.FixCascadeDeletesToRestrict do
  use Ecto.Migration

  # In a PSP / orchestration system, records are NEVER hard-deleted.
  # The three `on_delete: :delete_all` FKs introduced in P13 were wrong:
  #   - routing_rules.merchant_id  → merchants      (cascade would erase routing history)
  #   - routing_rule_conditions.rule_id → routing_rules   (cascade would lose audit trail)
  #   - routing_rule_actions.rule_id    → routing_rules   (same)
  #   - invoice_line_items.invoice_id   → invoices        (invoices are VOIDED, never deleted)
  #   - invoice_deliveries.invoice_id   → invoices        (delivery audit must survive)
  #
  # All are replaced with ON DELETE RESTRICT so Postgres will refuse any attempt
  # to hard-delete a referenced parent — errors surface at the DB layer before
  # data can be lost.

  def up do
    # ── routing_rules.merchant_id ──────────────────────────────────────────────
    execute "ALTER TABLE routing_rules DROP CONSTRAINT routing_rules_merchant_id_fkey"

    execute "ALTER TABLE routing_rules ADD CONSTRAINT routing_rules_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE RESTRICT"

    # ── routing_rule_conditions.rule_id ───────────────────────────────────────
    execute "ALTER TABLE routing_rule_conditions DROP CONSTRAINT routing_rule_conditions_rule_id_fkey"

    execute "ALTER TABLE routing_rule_conditions ADD CONSTRAINT routing_rule_conditions_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES routing_rules(id) ON DELETE RESTRICT"

    # ── routing_rule_actions.rule_id ──────────────────────────────────────────
    execute "ALTER TABLE routing_rule_actions DROP CONSTRAINT routing_rule_actions_rule_id_fkey"

    execute "ALTER TABLE routing_rule_actions ADD CONSTRAINT routing_rule_actions_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES routing_rules(id) ON DELETE RESTRICT"

    # ── invoice_line_items.invoice_id ─────────────────────────────────────────
    execute "ALTER TABLE invoice_line_items DROP CONSTRAINT invoice_line_items_invoice_id_fkey"

    execute "ALTER TABLE invoice_line_items ADD CONSTRAINT invoice_line_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT"

    # ── invoice_deliveries.invoice_id ─────────────────────────────────────────
    execute "ALTER TABLE invoice_deliveries DROP CONSTRAINT invoice_deliveries_invoice_id_fkey"

    execute "ALTER TABLE invoice_deliveries ADD CONSTRAINT invoice_deliveries_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT"
  end

  def down do
    # Restore original (incorrect) cascade behaviour on rollback
    execute "ALTER TABLE routing_rules DROP CONSTRAINT routing_rules_merchant_id_fkey"

    execute "ALTER TABLE routing_rules ADD CONSTRAINT routing_rules_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE"

    execute "ALTER TABLE routing_rule_conditions DROP CONSTRAINT routing_rule_conditions_rule_id_fkey"

    execute "ALTER TABLE routing_rule_conditions ADD CONSTRAINT routing_rule_conditions_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES routing_rules(id) ON DELETE CASCADE"

    execute "ALTER TABLE routing_rule_actions DROP CONSTRAINT routing_rule_actions_rule_id_fkey"

    execute "ALTER TABLE routing_rule_actions ADD CONSTRAINT routing_rule_actions_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES routing_rules(id) ON DELETE CASCADE"

    execute "ALTER TABLE invoice_line_items DROP CONSTRAINT invoice_line_items_invoice_id_fkey"

    execute "ALTER TABLE invoice_line_items ADD CONSTRAINT invoice_line_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE"

    execute "ALTER TABLE invoice_deliveries DROP CONSTRAINT invoice_deliveries_invoice_id_fkey"

    execute "ALTER TABLE invoice_deliveries ADD CONSTRAINT invoice_deliveries_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE"
  end
end
