defmodule YagyeCore.Repo.Migrations.AddBankFieldsToSettlementControls do
  use Ecto.Migration

  def change do
    alter table(:merchant_settlement_controls) do
      add :settlement_bank_code, :string, null: true
      add :settlement_account_number, :string, null: true
      add :settlement_account_name, :string, null: true
    end
  end
end
