defmodule YagyeCore.Repo.Migrations.P16Step0ProvidersCapabilities do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :capabilities, :map, default: %{}, null: false
    end
  end
end
