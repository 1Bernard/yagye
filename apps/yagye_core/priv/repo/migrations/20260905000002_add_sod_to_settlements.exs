defmodule YagyeCore.Repo.Migrations.AddSodToSettlements do
  use Ecto.Migration

  def change do
    alter table(:settlements) do
      add :write_off_initiated_by, :text
      add :write_off_approved_by, :text
    end

    execute(
      """
      ALTER TABLE settlements
        ADD CONSTRAINT settlements_write_off_sod
        CHECK (
          write_off_approved_by IS NULL OR
          write_off_initiated_by IS NULL OR
          write_off_approved_by <> write_off_initiated_by
        )
      """,
      "ALTER TABLE settlements DROP CONSTRAINT settlements_write_off_sod"
    )
  end
end
