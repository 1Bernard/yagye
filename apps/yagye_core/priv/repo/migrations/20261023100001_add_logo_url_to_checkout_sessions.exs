defmodule YagyeCore.Repo.Migrations.AddLogoUrlToCheckoutSessions do
  use Ecto.Migration

  def change do
    alter table(:checkout_sessions) do
      add :logo_url, :text, null: true
    end
  end
end
