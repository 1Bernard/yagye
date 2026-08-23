defmodule YagyeCore.Repo.Migrations.CreateOutboxAndProjections do
  use Ecto.Migration

  def change do
    # -------------------------------------------------------------------------
    # outbox_messages — written in the SAME transaction as the state change.
    # bigserial pk so the relay can read in insertion order without a secondary
    # index scan. Relay polls: WHERE published_at IS NULL ORDER BY id LIMIT n.
    # -------------------------------------------------------------------------
    create table(:outbox_messages, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :event_id, :text, null: false
      add :aggregate_type, :text, null: false
      add :aggregate_id, :uuid, null: false
      add :aggregate_version, :integer, null: false
      add :event_type, :text, null: false
      add :event_version, :integer, null: false
      add :partition_key, :text, null: false
      add :merchant_id, :uuid
      add :destination, :text, null: false
      add :envelope, :map, null: false
      add :mode, :text, null: false
      add :published_at, :utc_datetime_usec
      add :publish_attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :occurred_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:outbox_messages, [:event_id])
    # relay reads unpublished rows ordered by id — partial index keeps it lean
    create index(:outbox_messages, [:id],
             where: "published_at IS NULL",
             name: :outbox_messages_unpublished_idx
           )

    # -------------------------------------------------------------------------
    # proj_payment_summaries — one row per payment, updated by projection worker.
    # aggregate_version is the version fence: apply only if incoming > stored.
    # -------------------------------------------------------------------------
    create table(:proj_payment_summaries, primary_key: false) do
      add :payment_id, :uuid, primary_key: true
      add :merchant_id, :uuid, null: false
      add :mode, :text, null: false
      add :aggregate_version, :integer, null: false
      add :state, :text, null: false
      add :method, :text, null: false
      add :provider_code, :text
      add :amount, :bigint, null: false
      add :currency, :string, size: 3, null: false
      add :net_amount, :bigint
      add :platform_fee, :bigint
      add :provider_fee, :bigint
      add :settlement_id, :uuid
      add :settlement_state, :text
      add :customer_reference, :text
      add :merchant_reference, :text
      add :created_at, :utc_datetime_usec, null: false
      add :last_transition_at, :utc_datetime_usec, null: false
      add :last_event_id, :text, null: false
    end

    create index(:proj_payment_summaries, [:merchant_id])
    create index(:proj_payment_summaries, [:merchant_id, :state])

    # -------------------------------------------------------------------------
    # proj_merchant_balances — money counters per merchant/currency/mode.
    # Deduped on event_id before incrementing (see projection worker).
    # Version fencing does NOT make counters idempotent — dedup does.
    # -------------------------------------------------------------------------
    create table(:proj_merchant_balances, primary_key: false) do
      add :merchant_id, :uuid, primary_key: true
      add :currency, :string, size: 3, primary_key: true
      add :mode, :text, primary_key: true
      add :available, :bigint, null: false, default: 0
      add :pending, :bigint, null: false, default: 0
      add :reserved, :bigint, null: false, default: 0
      add :in_transit, :bigint, null: false, default: 0
      add :lifetime_volume, :bigint, null: false, default: 0
      add :last_event_id, :text
      add :last_applied_at, :utc_datetime_usec
    end

    # -------------------------------------------------------------------------
    # proj_daily_merchant_metrics — volume counters, recomputed hourly from
    # source rather than deduped. A wrong count self-corrects; a wrong amount
    # on proj_merchant_balances would be a misstatement.
    # -------------------------------------------------------------------------
    create table(:proj_daily_merchant_metrics, primary_key: false) do
      add :merchant_id, :uuid, primary_key: true
      add :day, :date, primary_key: true
      add :currency, :string, size: 3, primary_key: true
      add :mode, :text, primary_key: true
      add :payment_count, :integer, null: false, default: 0
      add :succeeded_count, :integer, null: false, default: 0
      add :failed_count, :integer, null: false, default: 0
      add :gross_volume, :bigint, null: false, default: 0
      add :net_volume, :bigint, null: false, default: 0
      add :refund_volume, :bigint, null: false, default: 0
      add :chargeback_count, :integer, null: false, default: 0
    end
  end
end
