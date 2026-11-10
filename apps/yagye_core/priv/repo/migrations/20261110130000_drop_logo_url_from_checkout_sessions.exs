defmodule YagyeCore.Repo.Migrations.DropLogoUrlFromCheckoutSessions do
  use Ecto.Migration

  # logo_url was a per-session branding snapshot that pre-dated MCC.
  # Branding now lives in merchant_checkout_configs, so this column is dead.

  def change do
    alter table(:checkout_sessions) do
      remove :logo_url, :text
    end
  end
end
