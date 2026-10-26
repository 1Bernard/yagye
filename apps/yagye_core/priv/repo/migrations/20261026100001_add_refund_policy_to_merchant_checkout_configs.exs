defmodule YagyeCore.Repo.Migrations.AddRefundPolicyToMerchantCheckoutConfigs do
  use Ecto.Migration

  def change do
    alter table(:merchant_checkout_configs) do
      # How long after payment creation a refund can be initiated (days).
      # Default 180 days — conservative, covers BoG risk window.
      add :refund_window_days, :integer, default: 180, null: false

      # Whether the merchant can issue partial refunds (amount < original payment).
      add :partial_refunds_enabled, :boolean, default: true, null: false

      # Refunds above this pesewa amount route to the ops approval queue.
      # NULL means no approval threshold — all refunds are self-service.
      add :requires_approval_above_pesewas, :integer
    end

    create constraint(:merchant_checkout_configs, :refund_window_days_positive,
             check: "refund_window_days > 0"
           )

    create constraint(:merchant_checkout_configs, :refund_window_days_max_one_year,
             check: "refund_window_days <= 365"
           )

    create constraint(:merchant_checkout_configs, :requires_approval_above_pesewas_positive,
             check:
               "requires_approval_above_pesewas IS NULL OR requires_approval_above_pesewas > 0"
           )
  end
end
