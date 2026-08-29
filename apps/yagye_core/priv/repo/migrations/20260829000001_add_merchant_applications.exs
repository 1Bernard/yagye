defmodule YagyeCore.Repo.Migrations.AddMerchantApplications do
  use Ecto.Migration

  def change do
    # Add business-profile columns to merchants (captured from application form)
    alter table(:merchants) do
      add :industry, :text
      add :employee_range, :text
      add :annual_tpv_estimate_cents, :bigint
      add :website_url, :text
    end

    create table(:merchant_applications, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :status, :text, null: false, default: "submitted"

      # Contact person
      add :first_name, :text, null: false
      add :last_name, :text, null: false
      add :email, :text, null: false
      add :phone_number, :text
      add :job_title, :text

      # Business identity
      add :legal_name, :text, null: false
      add :trading_name, :text, null: false
      add :country, :string, size: 2, null: false
      add :default_currency, :string, size: 3, null: false
      add :industry, :text
      add :employee_range, :text
      add :annual_tpv_estimate_cents, :bigint
      add :website_url, :text
      add :use_case, :text
      add :expected_methods, {:array, :text}

      # Ops review
      add :reviewed_by, :text
      add :review_notes, :text
      add :reviewed_at, :utc_datetime_usec

      # Outcome
      add :approved_by, :text
      add :rejected_reason, :text

      # Linked merchant (set on approval)
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:merchant_applications, [:public_id])
    create index(:merchant_applications, [:email])
    create index(:merchant_applications, [:status])

    create constraint(:merchant_applications, :valid_status,
             check: "status IN ('submitted', 'under_review', 'approved', 'rejected')"
           )

    execute(
      "ALTER TABLE merchant_applications ADD CONSTRAINT sod_application_actors CHECK (approved_by IS NULL OR reviewed_by IS NULL OR approved_by <> reviewed_by)",
      "ALTER TABLE merchant_applications DROP CONSTRAINT IF EXISTS sod_application_actors"
    )
  end
end
