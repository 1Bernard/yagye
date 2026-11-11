defmodule YagyeCore.Repo.Migrations.ReaddTemplateIdToCheckoutSessions do
  use Ecto.Migration

  # Restoring template_id so the published template is snapped at session creation.
  # Component visibility (terms_checkbox, etc.) now drives LiveView behaviour.
  # on_delete: :nilify_all is a safety net — templates use status-based archiving, never hard deletes.
  def change do
    alter table(:checkout_sessions) do
      add :template_id, references(:checkout_templates, type: :uuid, on_delete: :nilify_all)
    end
  end
end
