defmodule YagyeCore.Repo.Migrations.AddReservedAmountToSettlementBatches do
  use Ecto.Migration

  def change do
    alter table(:settlement_batches) do
      # Portion of gross_amount withheld as rolling reserve for this batch.
      # net_amount = gross_amount - platform_fees - provider_fees - reserved_amount
      add :reserved_amount, :bigint, null: false, default: 0
    end

    create constraint(:settlement_batches, :reserved_amount_non_negative,
             check: "reserved_amount >= 0"
           )
  end
end
