defmodule YagyeCore.Repo.Migrations.AddDeregisteredAtToMerchantWebhookEndpoints do
  use Ecto.Migration

  def change do
    alter table(:merchant_webhook_endpoints) do
      add :deregistered_at, :utc_datetime_usec, null: true
    end

    create index(:merchant_webhook_endpoints, [:deregistered_at])
  end
end
