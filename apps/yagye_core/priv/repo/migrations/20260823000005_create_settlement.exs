defmodule YagyeCore.Repo.Migrations.CreateSettlement do
  use Ecto.Migration

  def change do
    # settlement_cadence drives the daily scheduler's cutoff hour and timezone.
    # Default {} means "use platform default" (23:00 Africa/Accra).
    alter table(:providers) do
      add :settlement_cadence, :map, default: %{}
    end

    create table(:settlement_batches, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :currency, :string, null: false
      add :mode, :string, null: false
      add :period_start, :utc_datetime_usec, null: false
      add :period_end, :utc_datetime_usec, null: false
      add :payment_count, :integer, null: false, default: 0
      add :gross_amount, :integer, null: false, default: 0
      add :state, :string, null: false, default: "pending"
      add :error, :string
      add :settled_at, :utc_datetime_usec

      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec)
    end

    create index(:settlement_batches, [:merchant_id])
    create index(:settlement_batches, [:state])
    create index(:settlement_batches, [:merchant_id, :currency, :mode, :state])

    alter table(:payments) do
      add :settlement_batch_id,
          references(:settlement_batches, type: :uuid, on_delete: :restrict),
          null: true
    end

    create index(:payments, [:settlement_batch_id])
  end
end
