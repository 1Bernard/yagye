defmodule Simulator.Repo.Migrations.CreateSimulatorTables do
  use Ecto.Migration

  def change do
    # ── gw_scenarios (control plane — define before accounts so accounts can FK to it) ──

    create table(:gw_scenarios, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :text, null: false
      add :active, :boolean, null: false, default: true
      add :is_default, :boolean, null: false, default: false
      add :seed, :integer
      add :latency_p50_ms, :integer, null: false, default: 80
      add :latency_p95_ms, :integer, null: false, default: 400
      add :latency_p99_ms, :integer, null: false, default: 1_200
      add :success_rate, :decimal, null: false, default: "0.900", precision: 4, scale: 3
      add :decline_rate, :decimal, null: false, default: "0.050", precision: 4, scale: 3
      add :provider_error_rate, :decimal, null: false, default: "0.010", precision: 4, scale: 3
      add :timeout_rate, :decimal, null: false, default: "0.040", precision: 4, scale: 3
      add :timeout_creates_charge, :boolean, null: false, default: false
      add :duplicate_webhook_rate, :decimal, null: false, default: "0.000", precision: 4, scale: 3
      add :out_of_order_rate, :decimal, null: false, default: "0.000", precision: 4, scale: 3
      add :webhook_drop_rate, :decimal, null: false, default: "0.000", precision: 4, scale: 3
      add :webhook_delay_max_ms, :integer, null: false, default: 0
      add :three_ds_required_rate, :decimal, null: false, default: "0.000", precision: 4, scale: 3
      add :auth_validity_hours, :integer, null: false, default: 24
      add :supports_partial_capture, :boolean, null: false, default: false
      add :supports_multiple_capture, :boolean, null: false, default: false
      add :supports_incremental_auth, :boolean, null: false, default: false
      add :supports_void, :boolean, null: false, default: true
      # authorisation|capture|settlement — when does the ARN appear?
      add :arn_issued_at, :text, null: false, default: "authorisation"
      add :settlement_discrepancy_rate, :decimal, null: false, default: "0.000", precision: 4, scale: 3
      add :settlement_missing_line_rate, :decimal, null: false, default: "0.000", precision: 4, scale: 3
      add :fee_drift_bps, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create unique_index(:gw_scenarios, [:name])
    # Enforces at most one default scenario
    create unique_index(:gw_scenarios, [:is_default], where: "is_default = true")

    # ── gw_accounts ───────────────────────────────────────────────────────────────

    create table(:gw_accounts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :account_ref, :text, null: false
      add :display_name, :text, null: false
      add :webhook_url, :text, null: false
      # Plaintext ON PURPOSE — readable for signing test payloads
      add :webhook_secret, :text, null: false
      # HS256|HS512|SHA256 — real providers differ
      add :webhook_signing_algorithm, :text, null: false, default: "HS256"
      # daily|t_plus_2|weekly
      add :settlement_cadence, :text, null: false, default: "daily"
      add :settlement_cutoff_time, :time, null: false, default: "00:00:00"
      # Their timezone — batch-boundary bug lives here
      add :settlement_timezone, :text, null: false, default: "Africa/Accra"
      add :currency, :char, size: 3, null: false
      add :fee_percentage_bps, :integer, null: false, default: 150
      add :fee_fixed_minor, :bigint, null: false, default: 0
      add :default_scenario_id, references(:gw_scenarios, type: :uuid, on_delete: :restrict)
      add :created_at, :utc_datetime_usec, null: false

      # no updated_at — account settings are versioned via events in production
    end

    create unique_index(:gw_accounts, [:account_ref])

    create constraint(:gw_accounts, :valid_settlement_cadence,
             check: "settlement_cadence IN ('daily','t_plus_2','weekly')"
           )

    create constraint(:gw_accounts, :valid_signing_algorithm,
             check: "webhook_signing_algorithm IN ('HS256','HS512','SHA256')"
           )

    # ── gw_api_keys ───────────────────────────────────────────────────────────────

    create table(:gw_api_keys, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :delete_all), null: false
      # SHA-256 of the raw key
      add :key_hash, :text, null: false
      add :label, :text, null: false
      add :active, :boolean, null: false, default: true
      add :created_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
    end

    create unique_index(:gw_api_keys, [:account_id, :key_hash])
    create index(:gw_api_keys, [:key_hash])

    # ── gw_charges ────────────────────────────────────────────────────────────────

    create table(:gw_charges, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :charge_ref, :text, null: false
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :restrict), null: false
      add :idempotency_key, :text
      add :amount_minor, :bigint, null: false
      add :currency, :char, size: 3, null: false
      # CARD|WALLET|BANK
      add :instrument_type, :text, null: false
      # PENDING_AUTH|AUTHORISED|CAPTURED|PARTIALLY_CAPTURED|VOIDED|DECLINED|REVERSED|AUTH_EXPIRED
      add :state, :text, null: false, default: "PENDING_AUTH"
      add :authorised_amount_minor, :bigint
      add :captured_amount_minor, :bigint, null: false, default: 0
      add :auth_expires_at, :utc_datetime_usec
      add :authorised_at, :utc_datetime_usec
      add :voided_at, :utc_datetime_usec
      add :decline_code, :text
      add :auth_code, :text
      # Retrieval Reference Number
      add :rrn, :text
      # Acquirer Reference Number — issued at auth, capture, or settlement depending on scenario
      add :arn, :text
      add :scenario_id, references(:gw_scenarios, type: :uuid, on_delete: :restrict)
      add :seed, :integer
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_charges, [:charge_ref])
    create unique_index(:gw_charges, [:account_id, :idempotency_key], where: "idempotency_key IS NOT NULL")
    create index(:gw_charges, [:account_id, :created_at])

    create constraint(:gw_charges, :valid_instrument_type,
             check: "instrument_type IN ('CARD','WALLET','BANK')"
           )

    create constraint(:gw_charges, :positive_amount, check: "amount_minor > 0")

    # ── gw_charge_events ─────────────────────────────────────────────────────────

    create table(:gw_charge_events, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      add :sequence, :integer, null: false
      add :event_type, :text, null: false
      add :from_state, :text
      add :to_state, :text
      add :payload, :jsonb, null: false, default: "{}"
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_charge_events, [:charge_id, :sequence])

    # ── gw_card_data ──────────────────────────────────────────────────────────────

    create table(:gw_card_data, primary_key: false) do
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict),
        primary_key: true,
        null: false

      # SCENARIO numbers only — 4000 0000 0000 0002 = DECLINED, 4000 0000 0000 0119 = TIMEOUT
      add :scenario_pan, :text, null: false
      add :brand, :text
      add :last4, :char, size: 4
      add :bin, :char, size: 8
      add :exp_month, :smallint
      add :exp_year, :smallint
      # tok_sim_…
      add :token, :text, null: false
      add :avs_result, :text
      add :cvv_result, :text
    end

    # ── gw_three_ds_sessions ──────────────────────────────────────────────────────

    create table(:gw_three_ds_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      add :acs_ref, :text, null: false
      add :required, :boolean, null: false
      # FRICTIONLESS|CHALLENGE
      add :flow, :text, null: false
      # APPROVED|DECLINED|ABANDONED|TIMEOUT
      add :outcome, :text
      add :eci, :char, size: 2
      add :cavv, :text
      add :liability_shift, :boolean
      # Force browser-return-vs-webhook race in either order
      add :redirect_delay_ms, :integer
      add :challenge_started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
    end

    create unique_index(:gw_three_ds_sessions, [:acs_ref])
    create index(:gw_three_ds_sessions, [:charge_id])

    # ── gw_wallet_prompts ─────────────────────────────────────────────────────────

    create table(:gw_wallet_prompts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      # MTN|TELECEL|AIRTELTIGO
      add :network, :text, null: false
      # FAKE NUMBERS ONLY — 024000000x scenario range
      add :msisdn, :text, null: false
      # SENT|APPROVED|DECLINED|EXPIRED
      add :prompt_state, :text, null: false, default: "SENT"
      # "Human presses a button" delay
      add :approval_delay_ms, :integer, null: false, default: 3_000
      # From name enquiry
      add :account_name, :text
      add :sent_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
    end

    create index(:gw_wallet_prompts, [:charge_id])

    create constraint(:gw_wallet_prompts, :valid_network,
             check: "network IN ('MTN','TELECEL','AIRTELTIGO')"
           )

    # ── gw_name_enquiries ─────────────────────────────────────────────────────────

    create table(:gw_name_enquiries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict)
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :restrict), null: false
      # MTN|TELECEL|AIRTELTIGO
      add :network, :text, null: false
      # FAKE NUMBERS ONLY — 024000000x range
      add :msisdn, :text, null: false
      # FOUND|NOT_FOUND|TIMEOUT|NETWORK_ERROR
      add :outcome, :text, null: false
      add :account_name, :text
      add :delay_ms, :integer, null: false, default: 200
      add :queried_at, :utc_datetime_usec, null: false
    end

    create index(:gw_name_enquiries, [:account_id, :msisdn])

    # ── gw_captures ───────────────────────────────────────────────────────────────

    create table(:gw_captures, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :capture_ref, :text, null: false
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      add :sequence, :integer, null: false
      add :amount_minor, :bigint, null: false
      add :is_final, :boolean, null: false
      # OK|EXCEEDS_AUTH|AUTH_EXPIRED|ALREADY_FINAL|DECLINED
      add :outcome, :text, null: false
      # ARN issued here, not at authorisation — the omission that breaks refund tracing
      add :arn, :text
      add :captured_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_captures, [:capture_ref])
    create unique_index(:gw_captures, [:charge_id, :sequence])

    # ── gw_incremental_auths ──────────────────────────────────────────────────────

    create table(:gw_incremental_auths, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      add :sequence, :integer, null: false
      add :additional_amount_minor, :bigint, null: false
      # OK|DECLINED|NOT_SUPPORTED
      add :outcome, :text, null: false
      add :requested_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_incremental_auths, [:charge_id, :sequence])

    # ── gw_reversals ─────────────────────────────────────────────────────────────

    create table(:gw_reversals, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :reversal_ref, :text, null: false
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      add :amount_minor, :bigint, null: false
      add :currency, :char, size: 3, null: false
      # REQUESTED|OK|FAILED
      add :state, :text, null: false, default: "REQUESTED"
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_reversals, [:reversal_ref])
    create index(:gw_reversals, [:charge_id])

    # ── gw_refunds ────────────────────────────────────────────────────────────────

    create table(:gw_refunds, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      # RF_… — their reference, not ours
      add :refund_ref, :text, null: false
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :restrict), null: false
      add :amount_minor, :bigint, null: false
      add :currency, :char, size: 3, null: false
      # REQUESTED|OK|PARTIAL|FAILED
      add :state, :text, null: false, default: "REQUESTED"
      # NULL until settlement confirms
      add :refund_arn, :text
      add :fee_minor, :bigint, null: false, default: 0
      # ORIGINAL_NOT_FOUND|ALREADY_REFUNDED|AMOUNT_EXCEEDS_ORIGINAL|WINDOW_EXPIRED
      add :failure_code, :text
      # delayed_arn|fee_surprise|partial_only
      add :injected_defect, :text
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_refunds, [:refund_ref])
    create index(:gw_refunds, [:charge_id])

    create constraint(:gw_refunds, :positive_amount, check: "amount_minor > 0")
    create constraint(:gw_refunds, :non_negative_fee, check: "fee_minor >= 0")

    # ── gw_chargebacks ────────────────────────────────────────────────────────────

    create table(:gw_chargebacks, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      # CB_… — their reference
      add :chargeback_ref, :text, null: false
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict), null: false
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :restrict), null: false
      add :amount_minor, :bigint, null: false
      add :currency, :char, size: 3, null: false
      # FRAUD|NOT_RECEIVED|DUPLICATE|NOT_AS_DESCRIBED
      add :reason_code, :text, null: false
      # CARD|WALLET|BANK — stage vocabulary differs by instrument
      add :instrument_type, :text, null: false
      # Card: RETRIEVAL|FIRST_CHARGEBACK|REPRESENTMENT|PRE_ARBITRATION
      # Wallet: RAISED|RESPONDED|ESCALATED
      add :stage, :text, null: false
      # RAISED|RESPONDED|WON|LOST
      add :state, :text, null: false, default: "RAISED"
      # NULL until final
      add :outcome, :text
      add :outcome_at, :utc_datetime_usec
      add :evidence_due_at, :utc_datetime_usec, null: false
      # missed_deadline|short_deadline|duplicate_notification
      add :injected_defect, :text
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_chargebacks, [:chargeback_ref])
    create index(:gw_chargebacks, [:charge_id])

    # ── gw_disbursements ──────────────────────────────────────────────────────────

    create table(:gw_disbursements, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      # DISB_… — their reference
      add :disbursement_ref, :text, null: false
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :restrict), null: false
      add :amount_minor, :bigint, null: false
      add :currency, :char, size: 3, null: false
      # BANK|WALLET
      add :destination_type, :text, null: false
      # Fake account/msisdn — scenario numbers only
      add :destination_ref, :text, null: false
      # SUBMITTED|PAID|RETURNED|FAILED
      add :state, :text, null: false, default: "SUBMITTED"
      # INVALID_ACCOUNT|LIMIT_EXCEEDED|ACCOUNT_CLOSED
      add :failure_code, :text
      # A payout can bounce DAYS after PAID
      add :return_reason, :text
      add :paid_at, :utc_datetime_usec
      add :returned_at, :utc_datetime_usec
      # Gap between SUBMITTED and PAID
      add :confirmation_delay_ms, :integer, null: false, default: 5_000
      # delayed_confirmation|return_after_paid|silent_failure
      add :injected_defect, :text
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_disbursements, [:disbursement_ref])
    create index(:gw_disbursements, [:account_id])

    # ── gw_settlement_files ───────────────────────────────────────────────────────

    create table(:gw_settlement_files, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :restrict), null: false
      add :file_ref, :text, null: false
      add :settlement_date, :date, null: false
      # JSON|CSV|FIXED_WIDTH
      add :format, :text, null: false, default: "JSON"
      add :currency, :char, size: 3, null: false
      add :gross_minor, :bigint, null: false
      add :fee_minor, :bigint, null: false
      add :net_minor, :bigint, null: false
      add :line_count, :integer, null: false
      # missing_line|duplicate_line|short_amount|fee_drift|malformed_lines|late_line
      add :injected_defect, :text
      add :generated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gw_settlement_files, [:file_ref])
    create index(:gw_settlement_files, [:account_id, :settlement_date])

    # ── gw_settlement_lines ───────────────────────────────────────────────────────

    create table(:gw_settlement_lines, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :file_id, references(:gw_settlement_files, type: :uuid, on_delete: :restrict), null: false
      add :line_number, :integer, null: false
      add :charge_ref, :text
      # CHARGE|REVERSAL|FEE|ADJUSTMENT
      add :line_type, :text, null: false
      add :gross_minor, :bigint
      add :fee_minor, :bigint
      add :net_minor, :bigint
      add :value_date, :date
      # When true, row is written deliberately broken
      add :malformed, :boolean, null: false, default: false
    end

    create unique_index(:gw_settlement_lines, [:file_id, :line_number])

    # ── gw_webhook_deliveries ─────────────────────────────────────────────────────

    create table(:gw_webhook_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :account_id, references(:gw_accounts, type: :uuid, on_delete: :restrict), null: false
      add :charge_id, references(:gw_charges, type: :uuid, on_delete: :restrict)
      # Our event id — Yagye dedupes on it, so we deliberately reuse it for duplicate tests
      add :event_id, :text, null: false
      add :event_type, :text, null: false
      add :payload, :jsonb, null: false, default: "{}"
      add :signature, :text, null: false
      # Delay injection lives here
      add :scheduled_for, :utc_datetime_usec, null: false
      # >1 = deliberate duplicate
      add :delivery_number, :integer, null: false, default: 1
      add :out_of_order, :boolean, null: false, default: false
      # A webhook we deliberately never send
      add :dropped, :boolean, null: false, default: false
      add :attempted_at, :utc_datetime_usec
      add :response_status, :integer
    end

    create index(:gw_webhook_deliveries, [:account_id])
    create index(:gw_webhook_deliveries, [:charge_id])
    create index(:gw_webhook_deliveries, [:scheduled_for])
  end
end
