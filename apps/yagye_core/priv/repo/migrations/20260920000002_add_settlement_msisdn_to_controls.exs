defmodule YagyeCore.Repo.Migrations.AddSettlementMsisdnToControls do
  use Ecto.Migration

  def change do
    alter table(:merchant_settlement_controls) do
      # MSISDN the merchant wants to receive mobile-money settlement payouts on.
      # E.g. "233241000001" (international format, no leading +).
      # Required for native-rail disbursements (MTN MoMo, AirtelTigo, etc.).
      # Null means bank transfer only or not yet configured.
      add :settlement_msisdn, :string, null: true
    end
  end
end
