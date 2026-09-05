defmodule YagyeCore.Repo.Migrations.AddSodToPricingRules do
  use Ecto.Migration

  def change do
    alter table(:pricing_rules) do
      add :created_by, :text
      add :approved_by, :text
    end

    execute(
      """
      ALTER TABLE pricing_rules
        ADD CONSTRAINT pricing_rules_sod
        CHECK (approved_by IS NULL OR created_by IS NULL OR approved_by <> created_by)
      """,
      "ALTER TABLE pricing_rules DROP CONSTRAINT pricing_rules_sod"
    )
  end
end
