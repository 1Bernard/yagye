defmodule YagyeCore.Repo.Migrations.AddProviderKind do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :kind, :text, null: false, default: "native_rail"
    end
  end
end
