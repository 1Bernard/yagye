defmodule YagyeCore.Repo.Migrations.CreateComplianceTables do
  use Ecto.Migration

  def change do
    # ── Screening providers (new table) ───────────────────────────────────────
    create table(:screening_providers, primary_key: false) do
      add :code, :text, primary_key: true
      add :display_name, :text, null: false
      add :adapter_module, :text, null: false
      add :supported_lists, {:array, :text}, null: false
      add :default_lists, {:array, :text}, null: false
      add :active, :boolean, null: false, default: true
      add :inserted_at, :utc_datetime_usec, null: false
    end

    execute(
      """
      INSERT INTO screening_providers (code, display_name, adapter_module, supported_lists, default_lists, active, inserted_at)
      VALUES (
        'stub',
        'Stub Screening Adapter',
        'Elixir.YagyeCore.Compliance.Adapters.StubScreeningAdapter',
        ARRAY['pep','sanctions_ofac','sanctions_eu','sanctions_un','sanctions_uk_hmt'],
        ARRAY['pep','sanctions_ofac','sanctions_eu','sanctions_un','sanctions_uk_hmt'],
        true,
        NOW()
      )
      ON CONFLICT (code) DO NOTHING
      """,
      "DELETE FROM screening_providers WHERE code = 'stub'"
    )

    # ── Add indexes to existing beneficial_owners ─────────────────────────────
    create_if_not_exists index(:beneficial_owners, [:merchant_id])

    # ── Add indexes to existing kyb_documents ─────────────────────────────────
    create_if_not_exists index(:kyb_documents, [:merchant_id])

    # ── Augment existing screening_hits ───────────────────────────────────────
    # Add columns that were missing from the original migration
    alter table(:screening_hits) do
      add_if_not_exists :screening_request_id, :uuid
      add_if_not_exists :pep_tier, :integer
      add_if_not_exists :rca_relationship, :text
      add_if_not_exists :raised_by, :text
    end

    create_if_not_exists index(:screening_hits, [:screening_request_id])
    create_if_not_exists index(:screening_hits, [:subject_type, :subject_id])

    # Fix the subject_type CHECK — original was missing 'beneficial_owner' and 'customer'
    execute(
      "ALTER TABLE screening_hits DROP CONSTRAINT IF EXISTS valid_subject_type",
      "ALTER TABLE screening_hits ADD CONSTRAINT valid_subject_type CHECK (subject_type = ANY (ARRAY['entity','director','ubo']))"
    )

    execute(
      "ALTER TABLE screening_hits ADD CONSTRAINT valid_subject_type CHECK (subject_type = ANY (ARRAY['entity','beneficial_owner','director','customer']))",
      "ALTER TABLE screening_hits DROP CONSTRAINT IF EXISTS valid_subject_type"
    )

    execute(
      "ALTER TABLE screening_hits ADD CONSTRAINT sod_disposition CHECK (dispositioned_by IS NULL OR raised_by IS NULL OR dispositioned_by <> raised_by)",
      "ALTER TABLE screening_hits DROP CONSTRAINT IF EXISTS sod_disposition"
    )

    # ── Screening subjects (new table) ────────────────────────────────────────
    create table(:screening_subjects, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :subject_type, :text, null: false
      add :subject_id, :uuid, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :screening_status, :text, null: false, default: "pending"
      add :enrolled_at, :utc_datetime_usec, null: false
      add :last_screened_at, :utc_datetime_usec
      add :next_screening_at, :utc_datetime_usec
      add :screening_frequency_days, :integer, null: false, default: 365
      add :risk_override, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:screening_subjects, [:subject_type, :subject_id])
    create index(:screening_subjects, [:merchant_id])
    create index(:screening_subjects, [:next_screening_at])

    create constraint(:screening_subjects, :valid_subject_type,
             check: "subject_type IN ('entity', 'beneficial_owner', 'director', 'customer')"
           )

    create constraint(:screening_subjects, :valid_screening_status,
             check:
               "screening_status IN ('pending', 'clean', 'potential_match', 'confirmed_pep', 'confirmed_match_blocked', 'cleared', 'suspended')"
           )

    # ── Screening requests (new table) ────────────────────────────────────────
    create table(:screening_requests, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :subject_id, references(:screening_subjects, type: :uuid, on_delete: :restrict),
        null: false

      add :provider_code, :text, null: false
      add :trigger, :text, null: false
      add :lists_checked, {:array, :text}, null: false
      add :search_ref, :text
      add :status, :text, null: false, default: "pending"
      add :match_count, :integer
      add :hit_count, :integer
      add :raw_response, :map
      add :error, :text
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:screening_requests, [:subject_id])

    create unique_index(:screening_requests, [:provider_code, :search_ref],
             where: "search_ref IS NOT NULL",
             name: :screening_requests_provider_code_search_ref_index
           )

    create constraint(:screening_requests, :valid_trigger,
             check: "trigger IN ('onboarding', 'periodic', 'manual', 'transaction_threshold')"
           )

    create constraint(:screening_requests, :valid_status,
             check: "status IN ('pending', 'completed', 'failed', 'timed_out')"
           )

    # Add FK from screening_hits to screening_requests now that the table exists
    execute(
      "ALTER TABLE screening_hits ADD CONSTRAINT screening_hits_screening_request_id_fkey FOREIGN KEY (screening_request_id) REFERENCES screening_requests(id) ON DELETE RESTRICT",
      "ALTER TABLE screening_hits DROP CONSTRAINT IF EXISTS screening_hits_screening_request_id_fkey"
    )
  end
end
