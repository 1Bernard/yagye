defmodule YagyeCore.Repo.Migrations.CreatePricingAndCustomers do
  use Ecto.Migration

  def change do
    # ── pricing_plans ──────────────────────────────────────────────────────────
    create table(:pricing_plans, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:public_id, :text, null: false)
      add(:name, :text, null: false)
      add(:version, :integer, null: false)
      add(:currency, :string, size: 3, null: false)
      add(:fee_mode, :text, null: false)
      add(:effective_from, :utc_datetime_usec, null: false)
      add(:effective_to, :utc_datetime_usec)
      add(:monthly_fee, :bigint, null: false, default: 0)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:pricing_plans, [:public_id]))
    create(unique_index(:pricing_plans, [:name, :version]))

    # ── pricing_rules ──────────────────────────────────────────────────────────
    create table(:pricing_rules, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :plan_id,
        references(:pricing_plans, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:specificity, :integer, null: false)
      add(:method, :text)
      add(:provider_code, :text)
      add(:card_brand, :text)
      add(:region, :string, size: 2)
      add(:amount_min, :bigint)
      add(:amount_max, :bigint)
      add(:percentage_bps, :integer, null: false, default: 0)
      add(:fixed_amount, :bigint, null: false, default: 0)
      add(:minimum_fee, :bigint)
      add(:maximum_fee, :bigint)
      add(:rounding, :text, null: false, default: "half_up")
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:pricing_rules, [:plan_id]))

    # ── fee_records ────────────────────────────────────────────────────────────
    create table(:fee_records, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:source_type, :text, null: false)
      add(:source_id, :binary_id, null: false)
      add(:merchant_id, references(:merchants, type: :binary_id), null: false)
      add(:mode, :text, null: false)
      add(:party, :text, null: false)
      add(:fee_kind, :text, null: false)
      add(:amount, :bigint, null: false)
      add(:currency, :string, size: 3, null: false)
      add(:pricing_plan_id, references(:pricing_plans, type: :binary_id))
      add(:pricing_rule_id, references(:pricing_rules, type: :binary_id))
      add(:computation, :map, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:fee_records, [:source_type, :source_id, :party]))
    create(index(:fee_records, [:merchant_id]))

    # ── platform_fee_invoices ──────────────────────────────────────────────────
    create table(:platform_fee_invoices, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:public_id, :text, null: false)
      add(:merchant_id, references(:merchants, type: :binary_id), null: false)
      add(:mode, :text, null: false)
      add(:period_start, :date, null: false)
      add(:period_end, :date, null: false)
      add(:currency, :string, size: 3, null: false)
      add(:total_amount, :bigint, null: false)
      add(:collection_method, :text, null: false)
      add(:state, :text, null: false, default: "draft")

      add(:settled_against_settlement_id, :binary_id)

      add(:due_at, :utc_datetime_usec)
      add(:collected_at, :utc_datetime_usec)
      add(:collection_reference, :text)
      add(:inserted_at, :utc_datetime_usec, null: false)
      add(:updated_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:platform_fee_invoices, [:public_id]))

    create(
      unique_index(
        :platform_fee_invoices,
        [:merchant_id, :mode, :period_start, :period_end]
      )
    )

    # ── customers ──────────────────────────────────────────────────────────────
    create table(:customers, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:public_id, :text, null: false)
      add(:merchant_id, references(:merchants, type: :binary_id), null: false)
      add(:merchant_customer_ref, :text, null: false)
      add(:kyc_tier, :text, null: false, default: "tier_1")
      add(:kyc_verified_at, :utc_datetime_usec)
      add(:inserted_at, :utc_datetime_usec, null: false)
      add(:updated_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:customers, [:public_id]))
    create(unique_index(:customers, [:merchant_id, :merchant_customer_ref]))

    execute(
      "ALTER TABLE customers ADD CONSTRAINT customers_kyc_tier_check CHECK (kyc_tier IN ('tier_1', 'tier_2', 'tier_3'))",
      "ALTER TABLE customers DROP CONSTRAINT customers_kyc_tier_check"
    )

    # ── velocity_limits ────────────────────────────────────────────────────────
    create table(:velocity_limits, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:entity_type, :text, null: false)
      add(:risk_tier, :text, null: false)
      add(:payment_method, :text, null: false)
      add(:currency, :string, size: 3, null: false)
      add(:max_single_txn, :bigint)
      add(:max_daily, :bigint)
      add(:max_monthly, :bigint)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:velocity_limits, [:entity_type, :risk_tier, :payment_method, :currency]))

    # ── account_verifications ──────────────────────────────────────────────────
    create table(:account_verifications, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:merchant_id, references(:merchants, type: :binary_id), null: false)
      add(:payment_id, references(:payments, type: :binary_id))
      add(:verification_type, :text, null: false)
      add(:provider_code, :text, null: false)
      add(:account_hash, :text, null: false)
      add(:account_masked, :text, null: false)
      add(:network, :text)
      add(:bank_code, :text)
      add(:account_name_returned, :text)
      add(:kyc_tier_returned, :text)
      add(:name_match_score, :decimal, precision: 4, scale: 3)
      add(:state, :text, null: false, default: "pending")
      add(:raw_response, :map)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:account_verifications, [:merchant_id]))
    create(index(:account_verifications, [:payment_id]))
    create(index(:account_verifications, [:account_hash]))
  end
end
