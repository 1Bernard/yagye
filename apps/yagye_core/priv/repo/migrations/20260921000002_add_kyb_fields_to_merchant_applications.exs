defmodule YagyeCore.Repo.Migrations.AddKybFieldsToMerchantApplications do
  use Ecto.Migration

  def change do
    alter table(:merchant_applications) do
      add :business_type, :string
      add :registration_type, :string
      add :category, :string
    end
  end
end
