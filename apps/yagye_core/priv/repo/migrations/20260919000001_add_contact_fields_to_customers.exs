defmodule YagyeCore.Repo.Migrations.AddContactFieldsToCustomers do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      add :email, :string
      add :phone, :string
      add :name, :string
    end
  end
end
