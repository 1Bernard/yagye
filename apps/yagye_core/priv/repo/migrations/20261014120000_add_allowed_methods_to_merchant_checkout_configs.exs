defmodule YagyeCore.Repo.Migrations.AddAllowedMethodsToMerchantCheckoutConfigs do
  use Ecto.Migration

  def change do
    alter table(:merchant_checkout_configs) do
      add :allowed_methods, {:array, :text},
        null: false,
        default: ["mobile_money", "card", "bank_transfer"]
    end
  end
end
