defmodule YagyeCore.Repo.Migrations.AddRegistrationNumberToMerchants do
  use Ecto.Migration

  def change do
    alter table(:merchants) do
      add :registration_number, :text
    end
  end
end
