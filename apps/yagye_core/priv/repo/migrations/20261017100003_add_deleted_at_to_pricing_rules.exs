defmodule YagyeCore.Repo.Migrations.AddDeletedAtToPricingRules do
  use Ecto.Migration

  def change do
    alter table(:pricing_rules) do
      add :deleted_at, :utc_datetime_usec, null: true
    end

    create index(:pricing_rules, [:deleted_at])
  end
end
