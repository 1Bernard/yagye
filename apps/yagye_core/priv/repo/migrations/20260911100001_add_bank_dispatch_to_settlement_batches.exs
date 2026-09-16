defmodule YagyeCore.Repo.Migrations.AddBankDispatchToSettlementBatches do
  use Ecto.Migration

  def change do
    alter table(:settlement_batches) do
      add :bank_dispatch_ref, :text
      add :bank_dispatched_at, :utc_datetime_usec
    end
  end
end
