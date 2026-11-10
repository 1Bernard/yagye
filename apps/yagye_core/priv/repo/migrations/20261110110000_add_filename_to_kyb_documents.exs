defmodule YagyeCore.Repo.Migrations.AddFilenameToKybDocuments do
  use Ecto.Migration

  def change do
    alter table(:kyb_documents) do
      add :filename, :text
    end
  end
end
