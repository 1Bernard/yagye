defmodule YagyeCore.Repo.Migrations.AddStatusToMerchantReserves do
  use Ecto.Migration

  def change do
    alter table(:merchant_reserves) do
      add :status, :string, null: false, default: "pending_approval"
      add :acknowledged_by, :string
      add :acknowledged_at, :utc_datetime_usec
      add :notice_sent_at, :utc_datetime_usec
      add :auto_activates_at, :utc_datetime_usec
    end

    create index(:merchant_reserves, [:status])

    create index(:merchant_reserves, [:auto_activates_at],
             where: "status = 'awaiting_merchant_ack'",
             name: :merchant_reserves_auto_activate_idx
           )
  end
end
