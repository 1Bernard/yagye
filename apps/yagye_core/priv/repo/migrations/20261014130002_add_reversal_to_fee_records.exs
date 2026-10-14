defmodule YagyeCore.Repo.Migrations.AddReversalToFeeRecords do
  use Ecto.Migration

  def change do
    alter table(:fee_records) do
      # Links a reversal record back to the fee it reverses.
      add :reversal_of_id, references(:fee_records, type: :binary_id, on_delete: :nothing),
        null: true
    end

    create index(:fee_records, [:reversal_of_id])
  end
end
