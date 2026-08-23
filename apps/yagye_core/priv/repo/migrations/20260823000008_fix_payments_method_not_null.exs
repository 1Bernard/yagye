defmodule YagyeCore.Repo.Migrations.FixPaymentsMethodNotNull do
  use Ecto.Migration

  def up do
    # Backfill any NULL rows before adding the NOT NULL constraint.
    # On an empty dev DB this is a no-op; on a populated one it defaults to mobile_money
    # which is the dominant method in the West African market this platform targets.
    execute "UPDATE payments SET method = 'mobile_money' WHERE method IS NULL"

    alter table(:payments) do
      modify :method, :text, null: false
    end
  end

  def down do
    alter table(:payments) do
      modify :method, :text, null: true
    end
  end
end
