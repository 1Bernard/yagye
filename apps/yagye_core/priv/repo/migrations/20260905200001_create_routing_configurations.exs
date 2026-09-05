defmodule YagyeCore.Repo.Migrations.CreateRoutingConfigurations do
  use Ecto.Migration

  def change do
    create table(:routing_configurations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :merchant_id, :uuid
      add :scope, :text, null: false
      add :name, :text, null: false
      add :description, :text
      add :schema_version, :integer, null: false, default: 1
      add :graph_payload, :map, null: false
      add :compiled_rules, :map
      add :state, :text, null: false, default: "draft"
      add :published_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      timestamps()
    end

    create unique_index(:routing_configurations, [:public_id])
    create index(:routing_configurations, [:merchant_id, :state])
    create index(:routing_configurations, [:scope, :state])
  end
end
