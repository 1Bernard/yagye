defmodule YagyeCore.Repo.Migrations.AddFeeKindToPricingRules do
  use Ecto.Migration

  def change do
    alter table(:pricing_rules) do
      add :fee_kind, :string, null: false, default: "psp_margin"
    end
  end
end
