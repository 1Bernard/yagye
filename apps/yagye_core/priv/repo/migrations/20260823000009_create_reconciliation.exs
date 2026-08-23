defmodule YagyeCore.Repo.Migrations.CreateReconciliation do
  use Ecto.Migration

  def change do
    create table(:provider_settlement_reports, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict), null: false
      add :mode, :string, null: false
      add :report_date, :date, null: false
      add :source, :string, null: false
      add :raw_uri, :text, null: false
      add :checksum, :string, null: false
      add :line_count, :integer, null: false
      add :reported_total, :bigint, null: false
      add :currency, :string, size: 3, null: false
      add :ingested_at, :utc_datetime_usec, null: false
    end

    create unique_index(:provider_settlement_reports, [
             :provider_id,
             :mode,
             :report_date,
             :checksum
           ])

    create index(:provider_settlement_reports, [:provider_id, :report_date])

    create table(:provider_report_lines, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :report_id, references(:provider_settlement_reports, type: :uuid, on_delete: :restrict),
        null: false

      add :line_number, :integer, null: false
      add :provider_reference, :string
      add :transaction_type, :string, null: false
      add :gross_amount, :bigint
      add :fee_amount, :bigint
      add :net_amount, :bigint
      add :currency, :string, size: 3
      add :occurred_at, :utc_datetime_usec
      add :value_date, :date
      add :raw, :map, null: false
      add :match_state, :string, null: false, default: "unmatched"
    end

    create unique_index(:provider_report_lines, [:report_id, :line_number])
    create index(:provider_report_lines, [:report_id, :match_state])
    create index(:provider_report_lines, [:provider_reference])

    create table(:reconciliation_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :string, null: false
      add :kind, :string, null: false
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict)
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict)
      add :mode, :string, null: false
      add :scope_from, :utc_datetime_usec, null: false
      add :scope_to, :utc_datetime_usec, null: false
      add :state, :string, null: false, default: "created"
      add :left_count, :integer
      add :right_count, :integer
      add :matched_count, :integer
      add :break_count, :integer
      add :matched_value, :bigint
      add :break_value, :bigint
      add :currency, :string, size: 3
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:reconciliation_runs, [:public_id])
    create index(:reconciliation_runs, [:state])
    create index(:reconciliation_runs, [:merchant_id, :mode, :state])
    create index(:reconciliation_runs, [:provider_id, :mode, :scope_from, :scope_to])

    create table(:reconciliation_matches, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_id, references(:reconciliation_runs, type: :uuid, on_delete: :restrict),
        null: false

      add :strategy, :string, null: false
      add :confidence, :decimal, precision: 4, scale: 3, null: false
      add :left_type, :string, null: false
      add :left_ids, {:array, :binary_id}, null: false
      add :right_type, :string, null: false
      add :right_ids, {:array, :binary_id}, null: false
      add :amount_left, :bigint
      add :amount_right, :bigint
      add :currency, :string, size: 3
      add :auto_accepted, :boolean, null: false
      add :accepted_by, :string
      add :accepted_at, :utc_datetime_usec

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:reconciliation_matches, [:run_id])
    create index(:reconciliation_matches, [:run_id, :strategy])

    create table(:reconciliation_breaks, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :string, null: false

      add :run_id, references(:reconciliation_runs, type: :uuid, on_delete: :restrict),
        null: false

      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict)
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict)
      add :mode, :string, null: false
      add :classification, :string, null: false
      add :severity, :string, null: false
      add :state, :string, null: false, default: "detected"
      add :left_ref, :string
      add :right_ref, :string
      add :expected_amount, :bigint
      add :actual_amount, :bigint
      add :difference, :bigint
      add :currency, :string, size: 3
      add :evidence, :map, null: false, default: %{}
      add :assigned_to, :string
      add :resolution_code, :string
      add :resolution_note, :text
      add :resolving_entry_id, references(:ledger_entries, type: :uuid, on_delete: :nilify_all)
      add :detected_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :sla_due_at, :utc_datetime_usec
    end

    create unique_index(:reconciliation_breaks, [:public_id])
    create index(:reconciliation_breaks, [:run_id])
    create index(:reconciliation_breaks, [:state])
    create index(:reconciliation_breaks, [:merchant_id, :state])

    create index(:reconciliation_breaks, [:sla_due_at],
             where: "state NOT IN ('resolved', 'written_off')"
           )

    create table(:adjustment_approvals, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :break_id, references(:reconciliation_breaks, type: :uuid, on_delete: :restrict),
        null: false

      add :proposed_by, :string, null: false
      add :proposed_at, :utc_datetime_usec, null: false
      add :proposed_action, :map, null: false
      add :approved_by, :string
      add :approved_at, :utc_datetime_usec
      add :rejected_reason, :text

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:adjustment_approvals, [:break_id])

    execute(
      "ALTER TABLE adjustment_approvals ADD CONSTRAINT adjustment_approvals_sod CHECK (approved_by IS NULL OR approved_by <> proposed_by)",
      "ALTER TABLE adjustment_approvals DROP CONSTRAINT adjustment_approvals_sod"
    )

    alter table(:settlement_batches) do
      add :reconciliation_run_id,
          references(:reconciliation_runs, type: :uuid, on_delete: :nilify_all)
    end
  end
end
