defmodule YagyeCore.Repo.Migrations.AddIsPreviewToCheckoutSessions do
  use Ecto.Migration

  def change do
    alter table(:checkout_sessions) do
      add :is_preview, :boolean, default: false, null: false
    end

    create index(:checkout_sessions, [:is_preview], where: "is_preview = true")
  end
end
