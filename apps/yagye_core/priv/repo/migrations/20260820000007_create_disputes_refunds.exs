defmodule YagyeCore.Repo.Migrations.CreateDisputesRefunds do
  use Ecto.Migration

  def change do
    # ── Extend payment states ─────────────────────────────────────────────────
    drop constraint(:payments, :valid_state)

    create constraint(:payments, :valid_state,
             check:
               "state IN ('created','processing','requires_action','authorised','succeeded'," <>
                 "'failed','cancelled','indeterminate','disputed','refunded','chargebacked')"
           )

    # ── disputes ──────────────────────────────────────────────────────────────
    create table(:disputes, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      # Network that raised it: MTN|TELECEL|AIRTELTIGO|VISA|MASTERCARD|GH_INTERBANK
      add :network, :text, null: false
      # duplicate|fraud|credit_not_processed|product_not_received|subscription_cancelled
      add :reason, :text, null: false
      add :amount, :bigint, null: false
      add :currency, :char, size: 3, null: false
      # opened|evidence_required|under_review|resolved
      add :stage, :text, null: false, default: "opened"
      # won|lost|retracted — NULL until resolved
      add :outcome, :text
      add :evidence_due_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
      add :metadata, :jsonb, null: false, default: "{}"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:disputes, [:public_id])
    create index(:disputes, [:payment_id])
    create index(:disputes, [:merchant_id, :inserted_at])

    create constraint(:disputes, :valid_stage,
             check: "stage IN ('opened','evidence_required','under_review','resolved')"
           )

    create constraint(:disputes, :valid_outcome,
             check: "outcome IS NULL OR outcome IN ('won','lost','retracted')"
           )

    create constraint(:disputes, :positive_amount, check: "amount > 0")

    # ── refunds ───────────────────────────────────────────────────────────────
    create table(:refunds, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      # Set when refund retracts an open dispute
      add :dispute_id, references(:disputes, type: :uuid, on_delete: :restrict)
      add :amount, :bigint, null: false
      add :currency, :char, size: 3, null: false
      # duplicate|fraudulent|customer_request|dispute_retracted
      add :reason, :text, null: false
      # requested|succeeded|failed
      add :state, :text, null: false, default: "requested"
      add :failure_reason, :text
      add :metadata, :jsonb, null: false, default: "{}"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:refunds, [:public_id])
    create index(:refunds, [:payment_id])
    create index(:refunds, [:dispute_id])
    create index(:refunds, [:merchant_id, :inserted_at])

    create constraint(:refunds, :valid_reason,
             check: "reason IN ('duplicate','fraudulent','customer_request','dispute_retracted')"
           )

    create constraint(:refunds, :valid_state,
             check: "state IN ('requested','succeeded','failed')"
           )

    create constraint(:refunds, :positive_amount, check: "amount > 0")
  end
end
