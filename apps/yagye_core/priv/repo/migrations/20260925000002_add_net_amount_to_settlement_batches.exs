defmodule YagyeCore.Repo.Migrations.AddNetAmountToSettlementBatches do
  use Ecto.Migration

  def change do
    alter table(:settlement_batches) do
      add :net_amount, :bigint
      add :platform_fees, :bigint
    end
  end
end
