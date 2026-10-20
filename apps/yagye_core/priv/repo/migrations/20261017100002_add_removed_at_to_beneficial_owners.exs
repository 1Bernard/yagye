defmodule YagyeCore.Repo.Migrations.AddRemovedAtToBeneficialOwners do
  use Ecto.Migration

  def change do
    alter table(:beneficial_owners) do
      add :removed_at, :utc_datetime_usec, null: true
    end

    create index(:beneficial_owners, [:removed_at])
  end
end
