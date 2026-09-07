defmodule YagyeCore.Repo.Migrations.CreateMerchantWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:merchant_webhook_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :endpoint_id,
          references(:merchant_webhook_endpoints, type: :uuid, on_delete: :restrict),
          null: false

      add :event_id, :text, null: false
      add :event_type, :text, null: false
      add :attempt, :integer, null: false, default: 1
      add :state, :text, null: false, default: "pending"
      add :request_headers, :jsonb, null: false, default: "{}"
      add :request_body, :jsonb, null: false, default: "{}"
      add :response_status, :integer
      add :response_body, :text
      add :duration_ms, :integer
      add :next_attempt_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:merchant_webhook_deliveries, [:endpoint_id, :event_id, :attempt])
    create index(:merchant_webhook_deliveries, [:endpoint_id])
    create index(:merchant_webhook_deliveries, [:state])
    create index(:merchant_webhook_deliveries, [:inserted_at])
  end
end
