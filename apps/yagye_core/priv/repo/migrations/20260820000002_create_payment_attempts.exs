defmodule YagyeCore.Repo.Migrations.CreatePaymentAttempts do
  use Ecto.Migration

  def change do
    create table(:payment_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict), null: false
      add :attempt_number, :integer, null: false
      add :method, :text
      add :state, :text, null: false, default: "created"
      add :provider_reference, :text
      add :idempotency_token, :text, null: false
      add :response_code, :text
      add :response_message, :text
      add :error_class, :text
      add :latency_ms, :integer
      add :dispatched_at, :utc_datetime_usec
      add :raw_response, :map

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at, inserted_at: :inserted_at)
    end

    create unique_index(:payment_attempts, [:public_id])
    create unique_index(:payment_attempts, [:payment_id, :attempt_number])

    create unique_index(:payment_attempts, [:provider_id, :provider_reference],
             where: "provider_reference IS NOT NULL"
           )
  end
end
