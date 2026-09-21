defmodule YagyeCore.Repo.Migrations.AddKybFieldsToMerchants do
  use Ecto.Migration

  def change do
    alter table(:merchants) do
      add :business_type, :string
      add :registration_type, :string
      add :category, :string
      add :tin, :string
    end
  end
end
