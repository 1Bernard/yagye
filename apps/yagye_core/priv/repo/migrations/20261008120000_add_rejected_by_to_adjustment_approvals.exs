defmodule YagyeCore.Repo.Migrations.AddRejectedByToAdjustmentApprovals do
  use Ecto.Migration

  def change do
    alter table(:adjustment_approvals) do
      add :rejected_by, :text
      add :rejected_at, :utc_datetime_usec
    end
  end
end
