defmodule YagyeCore.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :code, :text, null: false
      add :display_name, :text, null: false
      add :adapter_module, :text, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at, inserted_at: :inserted_at)
    end

    create unique_index(:providers, [:code])
  end
end
