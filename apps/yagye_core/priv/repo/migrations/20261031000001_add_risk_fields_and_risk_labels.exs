defmodule YagyeCore.Repo.Migrations.AddRiskFieldsAndRiskLabels do
  use Ecto.Migration

  def change do
    # Add risk scoring fields to payments
    alter table(:payments) do
      add :risk_score, :numeric, precision: 5, scale: 4
      add :risk_decision, :string
      add :risk_flagged_at, :utc_datetime_usec
    end

    # risk_labels — analyst feedback loop for model retraining
    create table(:risk_labels, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false
      add :label, :string, null: false
      add :labelled_by, :string, null: false
      add :note, :text
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:risk_labels, [:payment_id])
    create index(:risk_labels, [:label])

    create constraint(:risk_labels, :valid_label,
             check: "label IN ('confirmed_fraud', 'false_positive', 'suspicious', 'legitimate')"
           )

    create constraint(:payments, :valid_risk_decision,
             check: "risk_decision IS NULL OR risk_decision IN ('allow', 'review', 'block')"
           )
  end
end
