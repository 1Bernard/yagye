defmodule YagyeCore.Repo.Migrations.CreateP1OperationalTables do
  use Ecto.Migration

  def change do
    # The claim is inserted BEFORE the work runs. A uniqueness constraint that
    # fires after the side effect is not idempotency — it is a race condition
    # with a narrow window.
    create table(:idempotency_keys, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all), null: false
      add :key, :text, null: false
      add :request_fingerprint, :text, null: false
      add :command_name, :text
      add :state, :text, null: false, default: "in_progress"
      add :lease_expires_at, :utc_datetime_usec
      add :response_status, :integer
      add :response_body, :map
      add :resource_type, :text
      add :resource_id, :uuid
      add :executed_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:idempotency_keys, [:merchant_id, :key])

    create constraint(:idempotency_keys, :valid_state,
      check: "state IN ('in_progress', 'completed', 'failed')"
    )

    # Append-only audit log for every inbound API call — including failures.
    # Partitioned monthly in production; the partition is an infrastructure
    # concern added in Phase 17, not here.
    create table(:api_requests, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict)
      add :api_key_id, references(:api_keys, type: :uuid, on_delete: :restrict)
      add :mode, :"yagye_mode"
      add :method, :text, null: false
      add :path, :text, null: false
      add :api_version, :text
      add :status, :integer, null: false
      add :duration_ms, :integer, null: false
      add :correlation_id, :text, null: false
      add :trace_id, :text
      add :idempotency_key, :text
      add :request_body_sha256, :text
      add :error_code, :text
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:api_requests, [:merchant_id, :inserted_at])
    create index(:api_requests, [:correlation_id])

    # Beneficial owners — natural persons (directors, UBOs). Personal data lives
    # in pii_vault under subject_ref; only the ref is stored here.
    create table(:beneficial_owners, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :subject_ref, references(:pii_vault, column: :subject_ref, type: :uuid, on_delete: :restrict),
        null: false
      add :ownership_bps, :integer
      add :role, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create constraint(:beneficial_owners, :valid_role,
      check: "role IN ('director', 'ubo', 'both')"
    )

    create constraint(:beneficial_owners, :ownership_bps_range,
      check: "ownership_bps IS NULL OR (ownership_bps >= 0 AND ownership_bps <= 10000)"
    )

    # KYB documents. Stored in S3 with SSE-KMS; only the s3_key lives here.
    # Statutory AML retention measured from the END of the relationship.
    create table(:kyb_documents, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :kind, :text, null: false
      add :s3_key, :text, null: false
      add :checksum, :text, null: false
      add :scanned_at, :utc_datetime_usec
      add :uploaded_by, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create constraint(:kyb_documents, :valid_kind,
      check: "kind IN ('incorporation', 'id', 'proof_of_address', 'bank_confirmation')"
    )

    # Screening hits from sanctions, PEP and adverse media checks.
    # A sanctions match is an absolute bar — there is no code path to approve one.
    # disposition_reason is mandatory on any status change: "who cleared this
    # and on what basis" is the whole audit question.
    create table(:screening_hits, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :subject_type, :text, null: false
      add :subject_id, :uuid, null: false
      add :list_type, :text, null: false
      add :list_source, :text, null: false
      add :matched_name, :text, null: false
      add :match_score, :decimal, precision: 4, scale: 3, null: false
      add :matched_attributes, {:array, :text}
      add :status, :text, null: false, default: "open"
      add :disposition_reason, :text
      add :dispositioned_by, :text
      add :dispositioned_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:screening_hits, [:merchant_id, :status])

    create constraint(:screening_hits, :valid_subject_type,
      check: "subject_type IN ('entity', 'director', 'ubo')"
    )

    create constraint(:screening_hits, :valid_list_type,
      check: "list_type IN ('sanctions', 'pep', 'adverse_media')"
    )

    create constraint(:screening_hits, :valid_status,
      check: "status IN ('open', 'false_positive', 'true_match_cleared', 'true_match_blocked')"
    )

    create constraint(:screening_hits, :disposition_requires_reason,
      check: "status = 'open' OR disposition_reason IS NOT NULL"
    )

    create constraint(:screening_hits, :sanctions_cannot_be_cleared,
      check: "list_type != 'sanctions' OR status NOT IN ('false_positive', 'true_match_cleared')"
    )
  end
end
