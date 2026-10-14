defmodule YagyeCore.Repo.Migrations.AddStatusToPricingPlans do
  use Ecto.Migration

  def change do
    alter table(:pricing_plans) do
      add :status, :string, default: "draft", null: false
      add :created_by, :string
      add :activated_by, :string
      add :activated_at, :utc_datetime_usec
    end

    create index(:pricing_plans, [:status])

    # SoD: the ops user who creates a plan cannot also be the one who activates it.
    # NULL activated_by means not yet activated — always allowed.
    execute(
      """
      ALTER TABLE pricing_plans
        ADD CONSTRAINT pricing_plans_sod
        CHECK (activated_by IS NULL OR created_by IS DISTINCT FROM activated_by)
      """,
      "ALTER TABLE pricing_plans DROP CONSTRAINT IF EXISTS pricing_plans_sod"
    )
  end
end
