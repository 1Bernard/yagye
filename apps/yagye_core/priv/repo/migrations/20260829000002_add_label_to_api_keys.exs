defmodule YagyeCore.Repo.Migrations.AddLabelToApiKeys do
  use Ecto.Migration

  def change do
    alter table(:api_keys) do
      add :label, :text, null: false, default: ""
    end
  end
end
