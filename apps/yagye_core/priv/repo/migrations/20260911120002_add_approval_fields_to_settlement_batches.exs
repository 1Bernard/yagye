defmodule YagyeCore.Repo.Migrations.AddApprovalFieldsToSettlementBatches do
  use Ecto.Migration

  def change do
    alter table(:settlement_batches) do
      add :dispatch_approved_by, :text
      add :dispatch_approved_at, :utc_datetime_usec
      add :dispatch_rejected_by, :text
      add :dispatch_rejected_at, :utc_datetime_usec
      add :dispatch_rejection_reason, :text
    end
  end
end
