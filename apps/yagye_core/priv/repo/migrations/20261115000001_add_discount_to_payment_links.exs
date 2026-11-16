defmodule YagyeCore.Repo.Migrations.AddDiscountToPaymentLinks do
  use Ecto.Migration

  def change do
    alter table(:payment_links) do
      add :discount_amount, :bigint, null: false, default: 0
    end

    create constraint(:payment_links, :non_negative_discount, check: "discount_amount >= 0")
  end
end
