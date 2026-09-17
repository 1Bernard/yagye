defmodule Simulator.Repo.Migrations.AddVirtualAccountToCharges do
  use Ecto.Migration

  def change do
    alter table(:gw_charges) do
      add :virtual_account_number, :text
      add :virtual_account_bank, :text
      add :virtual_account_name, :text
      add :virtual_account_expires_at, :utc_datetime_usec
      add :payment_reference, :text
    end

    create index(:gw_charges, [:virtual_account_number],
             where: "virtual_account_number IS NOT NULL"
           )
  end
end
