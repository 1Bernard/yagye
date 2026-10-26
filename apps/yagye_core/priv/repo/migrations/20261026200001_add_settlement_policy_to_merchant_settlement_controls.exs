defmodule YagyeCore.Repo.Migrations.AddSettlementPolicyToMerchantSettlementControls do
  use Ecto.Migration

  def change do
    alter table(:merchant_settlement_controls) do
      # T+N delay: 0 = no delay (ops must explicitly set to 1+ to activate T+N).
      # 1 = T+1 (next business day, Ghana standard per Paystack).
      add :settlement_delay_days, :integer, null: false, default: 0

      # Minimum payout threshold. GHS 50 (5000 pesewas) matches Paystack Ghana.
      add :minimum_payout_pesewas, :integer, null: false, default: 5000

      # Settlement frequency: daily (default), weekly (Mondays only), monthly (1st of month).
      add :settlement_frequency, :string, null: false, default: "daily"

      # Rolling reserve in basis points (100 bps = 1%). Default 0 for low-risk merchants.
      # Applied per-batch; funds are held for reserve_release_days.
      add :reserve_rate_bps, :integer, null: false, default: 0

      # Days to hold reserved funds before release. Industry standard: 90 days.
      add :reserve_release_days, :integer, null: false, default: 90

      # Allows merchant to trigger early settlement from the portal dashboard.
      add :early_settlement_enabled, :boolean, null: false, default: false

      # Ops hold: when true the scheduler skips this merchant entirely.
      add :on_hold, :boolean, null: false, default: false
      add :hold_reason, :text, null: true
    end

    create constraint(:merchant_settlement_controls, :settlement_delay_days_range,
             check: "settlement_delay_days BETWEEN 0 AND 7"
           )

    create constraint(:merchant_settlement_controls, :minimum_payout_pesewas_positive,
             check: "minimum_payout_pesewas >= 0"
           )

    create constraint(:merchant_settlement_controls, :settlement_frequency_valid,
             check: "settlement_frequency IN ('daily','weekly','monthly')"
           )

    create constraint(:merchant_settlement_controls, :reserve_rate_bps_range,
             check: "reserve_rate_bps BETWEEN 0 AND 2500"
           )

    create constraint(:merchant_settlement_controls, :reserve_release_days_range,
             check: "reserve_release_days BETWEEN 30 AND 365"
           )
  end
end
