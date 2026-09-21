defmodule YagyeCore.Repo.Migrations.ExpandKybDocuments do
  use Ecto.Migration

  def change do
    alter table(:kyb_documents) do
      add :label, :string
      add :status, :string, null: false, default: "pending_upload"
      add :required_for_business_types, {:array, :text}, null: false, default: []
      add :reviewer_notes, :text
      add :reviewed_by, :string
      add :reviewed_at, :utc_datetime_usec
    end
  end
end
