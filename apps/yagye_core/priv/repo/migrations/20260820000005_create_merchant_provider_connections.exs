defmodule YagyeCore.Repo.Migrations.CreateMerchantProviderConnections do
  use Ecto.Migration

  def change do
    create table(:merchant_provider_connections, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      # Lower priority wins. Enables failover: try priority=1, fall back to priority=2.
      add :priority, :integer, null: false, default: 1
      # Payment methods this connection handles (e.g. ["card", "mobile_money"])
      add :enabled_methods, {:array, :text}, null: false, default: []
      # active|paused|disabled — paused keeps config but stops routing
      add :status, :text, null: false, default: "active"

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at, inserted_at: :inserted_at)
    end

    create constraint(:merchant_provider_connections, :valid_mode,
      check: "mode IN ('simulation','sandbox','live')"
    )

    create constraint(:merchant_provider_connections, :valid_status,
      check: "status IN ('active','paused','disabled')"
    )

    create constraint(:merchant_provider_connections, :positive_priority,
      check: "priority >= 1"
    )

    create unique_index(:merchant_provider_connections, [:merchant_id, :provider_id, :mode])
    create index(:merchant_provider_connections, [:merchant_id, :mode, :status, :priority])
  end
end
