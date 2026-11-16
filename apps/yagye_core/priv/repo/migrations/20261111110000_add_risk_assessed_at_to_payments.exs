defmodule YagyeCore.Repo.Migrations.AddRiskAssessedAtToPayments do
  use Ecto.Migration

  # risk_assessed_at records when the scoring service returned a result for this
  # payment. Distinct from risk_flagged_at (analyst queue action) — allows
  # querying "was this payment scored at all?" even when decision was 'allow'.
  def change do
    alter table(:payments) do
      add :risk_assessed_at, :utc_datetime_usec
    end
  end
end
