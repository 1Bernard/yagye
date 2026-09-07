defmodule YagyeCore.Repo.Migrations.CreateMerchantWebhookEndpoints do
  use Ecto.Migration

  def change do
    create table(:merchant_webhook_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :url, :text, null: false
      add :secret_encrypted, :bytea, null: false
      add :subscribed_events, {:array, :text}, null: false, default: []
      add :active, :boolean, null: false, default: true
      add :consecutive_failures, :integer, null: false, default: 0
      add :disabled_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:merchant_webhook_endpoints, [:public_id])
    create index(:merchant_webhook_endpoints, [:merchant_id])
    create index(:merchant_webhook_endpoints, [:merchant_id, :mode])
    create index(:merchant_webhook_endpoints, [:merchant_id, :active])
  end
end
