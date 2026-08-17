defmodule YagyeCore.Repo.Migrations.CreateP1IdentityTables do
  use Ecto.Migration

  def up do
    # The mode a merchant operates in. simulation is granted on email verify,
    # live only on compliance approval. sandbox is a future environment.
    execute "CREATE TYPE yagye_mode AS ENUM ('simulation', 'sandbox', 'live')"

    # PII vault — one row per data subject. The KMS key is the only link between
    # a subject_ref and their personal data. Destroying the key (crypto-shredding)
    # makes every copy of ciphertext permanently unreadable in one operation.
    # Build this now with three tables; retrofitting it with forty is a rewrite.
    create table(:pii_vault, primary_key: false) do
      add :subject_ref, :uuid, primary_key: true
      add :kms_key_id, :text, null: false
      add :ciphertext, :binary, null: false
      add :subject_kind, :text, null: false
      add :erased_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create constraint(:pii_vault, :valid_subject_kind,
      check: "subject_kind IN ('customer', 'beneficial_owner', 'merchant_user')"
    )

    # The tenant boundary. Every money-bearing row in the system traces back here.
    create table(:merchants, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :legal_name, :text, null: false
      add :trading_name, :text, null: false
      add :country, :string, size: 2, null: false
      add :default_currency, :string, size: 3, null: false
      add :status, :text, null: false, default: "registered"
      add :onboarding_state, :text, null: false, default: "registered"
      add :risk_rating, :text
      add :settlement_schedule, :map, null: false, default: %{}
      add :pricing_plan_id, :uuid
      add :activity_state, :text, null: false, default: "active"
      add :last_transaction_at, :utc_datetime_usec
      add :baseline_daily_volume, :bigint
      add :quiet_since, :utc_datetime_usec
      add :api_version, :text, null: false, default: "2026-08-17"
      add :entitlements, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:merchants, [:public_id])

    create constraint(:merchants, :valid_status,
      check: "status IN ('registered','under_review','approved','active','suspended','terminated','rejected')"
    )

    create constraint(:merchants, :valid_onboarding_state,
      check: "onboarding_state IN ('registered','details_submitted','under_review','approved','rejected','more_info_required')"
    )

    create constraint(:merchants, :valid_activity_state,
      check: "activity_state IN ('active','quiet','dormant','inactive','blind')"
    )

    # Which modes a merchant is permitted to use. A merchant is usable in a mode
    # only if a row exists here — no implicit defaults.
    create table(:merchant_modes, primary_key: false) do
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all), null: false
      add :mode, :"yagye_mode", null: false
      add :enabled_at, :utc_datetime_usec, null: false
    end

    execute "ALTER TABLE merchant_modes ADD PRIMARY KEY (merchant_id, mode)"

    # API keys. publishable keys are safe for client-side use (no secret_hash).
    # secret keys are shown once; only the argon2id hash is stored.
    # key_prefix is the first 24 chars — displayed in logs and the portal so
    # ops can identify which key was used without exposing the secret.
    create table(:api_keys, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :"yagye_mode", null: false
      add :kind, :text, null: false
      add :key_prefix, :text, null: false
      add :secret_hash, :text
      add :scopes, {:array, :text}, null: false, default: []
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :created_by, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_keys, [:public_id])
    create unique_index(:api_keys, [:merchant_id, :mode, :key_prefix])

    create index(:api_keys, [:key_prefix],
      where: "revoked_at IS NULL",
      name: :api_keys_lookup
    )

    create constraint(:api_keys, :valid_kind,
      check: "kind IN ('publishable', 'secret')"
    )

    create constraint(:api_keys, :secret_hash_only_for_secret_keys,
      check: "(kind = 'secret' AND secret_hash IS NOT NULL) OR (kind = 'publishable' AND secret_hash IS NULL)"
    )
  end

  def down do
    drop table(:api_keys)
    drop table(:merchant_modes)
    drop table(:merchants)
    drop table(:pii_vault)
    execute "DROP TYPE yagye_mode"
  end
end
