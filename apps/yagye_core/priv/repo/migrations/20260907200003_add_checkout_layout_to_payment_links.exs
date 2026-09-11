defmodule YagyeCore.Repo.Migrations.AddCheckoutLayoutToPaymentLinks do
  use Ecto.Migration

  def change do
    alter table(:payment_links) do
      add :checkout_layout, :map, default: %{}
    end
  end
end
