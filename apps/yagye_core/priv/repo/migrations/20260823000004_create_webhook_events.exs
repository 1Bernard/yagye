defmodule YagyeCore.Repo.Migrations.CreateWebhookEvents do
  use Ecto.Migration

  def change do
    create table(:webhook_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :provider_code, :string, null: false
      add :event_id, :string, null: false
      add :event_type, :string, null: false
      add :raw_body, :text, null: false
      add :headers, :map, default: %{}
      add :state, :string, null: false, default: "pending"
      add :error, :string
      add :processed_at, :utc_datetime_usec

      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:webhook_events, [:provider_code, :event_id])
    create index(:webhook_events, [:state])
  end
end
