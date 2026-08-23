defmodule YagyeCore.Repo.Migrations.FixSettlementBatches do
  use Ecto.Migration

  def change do
    # Each batch belongs to one provider — cadence is per-provider, ledger accounts
    # are provider-scoped, and you can only disburse from a provider's pool of funds.
    alter table(:settlement_batches) do
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict), null: false
    end

    # Replace old index (no provider dimension) with correct composite.
    drop index(:settlement_batches, [:merchant_id, :currency, :mode, :state])

    create index(:settlement_batches, [:provider_id])
    create index(:settlement_batches, [:merchant_id, :provider_id, :currency, :mode, :state])

    # Idempotency guard: one batch per merchant+provider+currency+mode per period.
    # The scheduler must check this before inserting; the DB is the last line of defence.
    create unique_index(
             :settlement_batches,
             [:merchant_id, :provider_id, :currency, :mode, :period_start, :period_end]
           )

    # Partial index for the scheduler sweep:
    # SELECT ... FROM payments WHERE settlement_batch_id IS NULL AND state = 'succeeded'
    #   AND merchant_id = ? AND currency = ? AND mode = ?
    # Standard indexes do not cover IS NULL efficiently.
    execute(
      """
      CREATE INDEX payments_unsettled_idx
        ON payments (merchant_id, currency, mode)
        WHERE settlement_batch_id IS NULL AND state = 'succeeded'
      """,
      "DROP INDEX IF EXISTS payments_unsettled_idx"
    )
  end
end
