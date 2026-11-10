defmodule YagyeCore.Repo.Migrations.DropTemplateIdFromCheckoutSessions do
  use Ecto.Migration

  # template_id was intended to snap the published template at session creation
  # for layout immutability. Components are not yet driving checkout behaviour,
  # so the column is dead weight. Re-add when component config affects the
  # LiveView flow (e.g. terms_checkbox gating the pay button).

  def change do
    alter table(:checkout_sessions) do
      remove :template_id, :uuid
    end
  end
end
