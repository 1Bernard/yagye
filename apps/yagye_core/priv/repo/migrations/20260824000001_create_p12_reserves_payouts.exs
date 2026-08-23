defmodule YagyeCore.Repo.Migrations.CreateP12ReservesPayouts do
  use Ecto.Migration

  def change do
    # ── fx_rates ─────────────────────────────────────────────────────────────
    create table(:fx_rates, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :base, :char, size: 3, null: false
      add :quote, :char, size: 3, null: false
      add :rate, :decimal, precision: 20, scale: 10, null: false
      add :source, :text, null: false
      add :markup_bps, :integer, null: false
      add :quoted_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:fx_rates, [:base, :quote, :quoted_at])
    create index(:fx_rates, [:expires_at])

    # ── settlements ──────────────────────────────────────────────────────────
    create table(:settlements, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :currency, :char, size: 3, null: false
      add :period_start, :utc_datetime_usec, null: false
      add :period_end, :utc_datetime_usec, null: false
      add :state, :text, null: false, default: "expected"
      add :expected_gross, :bigint, null: false
      add :expected_provider_fees, :bigint, null: false
      add :expected_platform_fees, :bigint, null: false
      add :expected_refunds, :bigint, null: false
      add :expected_chargebacks, :bigint, null: false
      add :expected_net, :bigint, null: false
      add :reported_gross, :bigint
      add :reported_fees, :bigint
      add :reported_net, :bigint
      add :actual_received, :bigint
      add :provider_settlement_reference, :text
      add :value_date, :date
      add :reconciliation_run_id, :uuid
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:settlements, [:public_id])

    create unique_index(:settlements, [
             :merchant_id,
             :provider_id,
             :mode,
             :currency,
             :period_start,
             :period_end
           ])

    execute(
      "ALTER TABLE settlements ADD CONSTRAINT settlements_state_check CHECK (state IN ('expected','reported','matching','matched','mismatched','investigating','settled','written_off'))",
      "ALTER TABLE settlements DROP CONSTRAINT settlements_state_check"
    )

    execute(
      "ALTER TABLE settlements ADD COLUMN variance bigint GENERATED ALWAYS AS (CASE WHEN reported_net IS NOT NULL THEN reported_net - expected_net ELSE NULL END) STORED",
      "ALTER TABLE settlements DROP COLUMN variance"
    )

    # ── settlement_items ─────────────────────────────────────────────────────
    create table(:settlement_items, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :settlement_id, references(:settlements, type: :uuid, on_delete: :restrict), null: false
      add :source_type, :text, null: false
      add :source_id, :uuid, null: false
      add :gross_amount, :bigint, null: false
      add :provider_fee, :bigint, null: false, default: 0
      add :platform_fee, :bigint, null: false, default: 0
      add :net_amount, :bigint, null: false
      add :currency, :char, size: 3, null: false
      add :fx_rate, :decimal, precision: 20, scale: 10
      add :fx_source, :text
      add :fx_quoted_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:settlement_items, [:settlement_id, :source_type, :source_id])

    execute(
      "ALTER TABLE settlement_items ADD CONSTRAINT settlement_items_source_type_check CHECK (source_type IN ('payment_attempt','payment_capture','refund','chargeback','adjustment','fee'))",
      "ALTER TABLE settlement_items DROP CONSTRAINT settlement_items_source_type_check"
    )

    # ── merchant_reserves ────────────────────────────────────────────────────
    create table(:merchant_reserves, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :kind, :text, null: false
      add :percentage_bps, :integer
      add :fixed_amount, :bigint
      add :currency, :char, size: 3, null: false
      add :hold_days, :integer
      add :active, :boolean, null: false, default: true
      add :reason, :text
      add :created_by, :text
      add :approved_by, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:merchant_reserves, [:merchant_id, :active])

    execute(
      "ALTER TABLE merchant_reserves ADD CONSTRAINT merchant_reserves_kind_check CHECK (kind IN ('rolling','fixed','ad_hoc'))",
      "ALTER TABLE merchant_reserves DROP CONSTRAINT merchant_reserves_kind_check"
    )

    execute(
      "ALTER TABLE merchant_reserves ADD CONSTRAINT merchant_reserves_sod_check CHECK (approved_by IS NULL OR created_by IS NULL OR approved_by <> created_by)",
      "ALTER TABLE merchant_reserves DROP CONSTRAINT merchant_reserves_sod_check"
    )

    # ── reserve_holds ────────────────────────────────────────────────────────
    create table(:reserve_holds, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false

      add :reserve_id, references(:merchant_reserves, type: :uuid, on_delete: :restrict),
        null: false

      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false
      add :amount, :bigint, null: false
      add :currency, :char, size: 3, null: false
      add :mode, :text, null: false
      add :state, :text, null: false, default: "pending"
      add :held_at, :utc_datetime_usec, null: false
      add :release_at, :utc_datetime_usec, null: false
      add :released_at, :utc_datetime_usec
      add :drawn_at, :utc_datetime_usec
      add :draw_source_id, :uuid
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:reserve_holds, [:merchant_id, :state, :release_at])
    create index(:reserve_holds, [:payment_id])
    create unique_index(:reserve_holds, [:payment_id, :reserve_id])

    execute(
      "ALTER TABLE reserve_holds ADD CONSTRAINT reserve_holds_state_check CHECK (state IN ('pending','released','drawn'))",
      "ALTER TABLE reserve_holds DROP CONSTRAINT reserve_holds_state_check"
    )

    # ── payout_destinations ──────────────────────────────────────────────────
    create table(:payout_destinations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :kind, :text, null: false
      add :currency, :char, size: 3, null: false
      add :account_details_encrypted, :binary, null: false
      add :fingerprint, :text, null: false
      add :account_name_verified, :text
      add :verification_state, :text, null: false, default: "unverified"
      add :is_default, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: true
      add :hold_until, :utc_datetime_usec
      add :added_by, :text
      add :verified_by, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payout_destinations, [:public_id])
    create unique_index(:payout_destinations, [:merchant_id, :mode, :fingerprint])

    execute(
      "ALTER TABLE payout_destinations ADD CONSTRAINT payout_destinations_kind_check CHECK (kind IN ('bank','mobile_money'))",
      "ALTER TABLE payout_destinations DROP CONSTRAINT payout_destinations_kind_check"
    )

    execute(
      "ALTER TABLE payout_destinations ADD CONSTRAINT payout_destinations_verification_state_check CHECK (verification_state IN ('unverified','micro_deposit_sent','verified','failed'))",
      "ALTER TABLE payout_destinations DROP CONSTRAINT payout_destinations_verification_state_check"
    )

    execute(
      "ALTER TABLE payout_destinations ADD CONSTRAINT payout_destinations_sod_check CHECK (verified_by IS NULL OR added_by IS NULL OR verified_by <> added_by)",
      "ALTER TABLE payout_destinations DROP CONSTRAINT payout_destinations_sod_check"
    )

    # ── payouts ──────────────────────────────────────────────────────────────
    create table(:payouts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false

      add :destination_id,
          references(:payout_destinations, type: :uuid, on_delete: :restrict),
          null: false

      add :mode, :text, null: false
      add :amount, :bigint, null: false
      add :currency, :char, size: 3, null: false
      add :destination_type, :text, null: false
      add :destination_fingerprint, :text, null: false
      add :state, :text, null: false, default: "scheduled"
      add :provider_reference, :text
      add :scheduled_for, :date, null: false
      add :submitted_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :failure_code, :text
      add :returned_at, :utc_datetime_usec
      add :saga_state, :map, null: false, default: %{}
      add :requested_by, :text
      add :approved_by, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payouts, [:public_id])
    create index(:payouts, [:merchant_id, :state])
    create index(:payouts, [:scheduled_for, :state])

    execute(
      "ALTER TABLE payouts ADD CONSTRAINT payouts_state_check CHECK (state IN ('scheduled','validating','reserving','submitted','paid','returned','failed','cancelled'))",
      "ALTER TABLE payouts DROP CONSTRAINT payouts_state_check"
    )

    execute(
      "ALTER TABLE payouts ADD CONSTRAINT payouts_destination_type_check CHECK (destination_type IN ('bank','mobile_money'))",
      "ALTER TABLE payouts DROP CONSTRAINT payouts_destination_type_check"
    )

    execute(
      "ALTER TABLE payouts ADD CONSTRAINT payouts_sod_check CHECK (approved_by IS NULL OR requested_by IS NULL OR approved_by <> requested_by)",
      "ALTER TABLE payouts DROP CONSTRAINT payouts_sod_check"
    )

    # ── momo_float_balances ──────────────────────────────────────────────────
    create table(:momo_float_balances, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :network, :text, null: false
      add :mode, :text, null: false
      add :balance, :bigint, null: false
      add :currency, :char, size: 3, null: false
      add :low_water_mark, :bigint, null: false
      add :ledger_account_id, references(:ledger_accounts, type: :uuid, on_delete: :nilify_all)
      add :last_synced_at, :utc_datetime_usec, null: false
    end

    create unique_index(:momo_float_balances, [:network, :mode])

    # ── bank_statements ──────────────────────────────────────────────────────
    create table(:bank_statements, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :account_reference, :text, null: false
      add :mode, :text, null: false
      add :statement_date, :date, null: false
      add :source, :text, null: false
      add :raw_uri, :text, null: false
      add :checksum, :text, null: false
      add :opening_balance, :bigint, null: false
      add :closing_balance, :bigint, null: false
      add :currency, :char, size: 3, null: false
      add :ingested_at, :utc_datetime_usec, null: false
    end

    create unique_index(:bank_statements, [:account_reference, :statement_date, :checksum])

    # ── bank_statement_lines ─────────────────────────────────────────────────
    create table(:bank_statement_lines, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :statement_id, references(:bank_statements, type: :uuid, on_delete: :restrict),
        null: false

      add :line_number, :integer, null: false
      add :value_date, :date, null: false
      add :amount, :bigint, null: false
      add :currency, :char, size: 3, null: false
      add :narrative, :text, null: false
      add :bank_reference, :text
      add :counterparty, :text
      add :match_state, :text, null: false, default: "unmatched"
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:bank_statement_lines, [:statement_id, :line_number])
    create index(:bank_statement_lines, [:match_state])

    execute(
      "ALTER TABLE bank_statement_lines ADD CONSTRAINT bank_statement_lines_match_state_check CHECK (match_state IN ('unmatched','matched','disputed','written_off'))",
      "ALTER TABLE bank_statement_lines DROP CONSTRAINT bank_statement_lines_match_state_check"
    )
  end
end
