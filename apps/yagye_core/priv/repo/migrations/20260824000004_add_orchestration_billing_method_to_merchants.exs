defmodule YagyeCore.Repo.Migrations.AddOrchestrationBillingMethodToMerchants do
  use Ecto.Migration

  def change do
    alter table(:merchants) do
      add :orchestration_billing_method, :string
    end
  end
end
