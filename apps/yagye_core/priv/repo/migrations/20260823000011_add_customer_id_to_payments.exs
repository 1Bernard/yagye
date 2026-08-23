defmodule YagyeCore.Repo.Migrations.AddCustomerIdToPayments do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :customer_id, references(:customers, type: :uuid, on_delete: :nilify_all)
    end

    create index(:payments, [:customer_id])
  end
end
