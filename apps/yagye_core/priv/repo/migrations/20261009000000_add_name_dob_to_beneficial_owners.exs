defmodule YagyeCore.Repo.Migrations.AddNameDobToBeneficialOwners do
  use Ecto.Migration

  def change do
    alter table(:beneficial_owners) do
      add :subject_name, :text
      add :subject_dob, :date
    end
  end
end
