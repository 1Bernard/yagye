defmodule YagyeCore.Repo.Migrations.AddReceiptSettingsToMerchants do
  use Ecto.Migration

  def change do
    alter table(:merchants) do
      add :receipt_settings, :map, default: %{}, null: false
    end
  end
end
