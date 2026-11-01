defmodule YagyeCore.Repo.Migrations.AddEscrowToPaymentLinksAndCreateEscrowHolds do
  use Ecto.Migration

  def change do
    alter table(:payment_links) do
      add :escrow_enabled, :boolean, default: false, null: false
      add :escrow_hold_days, :integer, default: 3, null: false
      add :escrow_dispute_window_hours, :integer, default: 48, null: false
      add :escrow_auto_release_days, :integer, default: 7, null: false
    end

    create table(:escrow_holds, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :public_id, :string, null: false

      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false

      add :payment_link_id, references(:payment_links, type: :uuid, on_delete: :restrict),
        null: false

      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false

      add :amount, :bigint, null: false
      add :currency, :string, null: false, size: 3
      add :mode, :string, null: false
      add :state, :string, null: false, default: "held"

      add :buyer_confirmed_at, :utc_datetime_usec
      add :auto_release_at, :utc_datetime_usec, null: false
      add :dispute_window_ends_at, :utc_datetime_usec, null: false
      add :released_at, :utc_datetime_usec
      add :refunded_at, :utc_datetime_usec

      add :metadata, :map, default: %{}

      timestamps(inserted_at: :inserted_at, updated_at: :updated_at, type: :utc_datetime_usec)
    end

    create unique_index(:escrow_holds, [:public_id])
    create unique_index(:escrow_holds, [:payment_id])
    create index(:escrow_holds, [:merchant_id])
    create index(:escrow_holds, [:state])
    create index(:escrow_holds, [:auto_release_at])

    create constraint(:escrow_holds, :valid_state,
             check: "state IN ('held','disputed','released','refunded')"
           )

    create table(:escrow_dispute_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :public_id, :string, null: false

      add :escrow_hold_id,
          references(:escrow_holds, type: :uuid, on_delete: :restrict),
          null: false

      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false

      add :event_type, :string, null: false
      add :actor, :string, null: false
      add :note, :text
      add :metadata, :map, default: %{}

      timestamps(inserted_at: :inserted_at, updated_at: :updated_at, type: :utc_datetime_usec)
    end

    create unique_index(:escrow_dispute_events, [:public_id])
    create index(:escrow_dispute_events, [:escrow_hold_id])

    drop constraint(:payments, :valid_state)

    create constraint(:payments, :valid_state,
             check:
               "state IN ('created','processing','requires_action','authorised','succeeded'," <>
                 "'failed','cancelled','indeterminate','disputed','refunded','partially_refunded'," <>
                 "'chargebacked','escrow_held','escrow_released','escrow_disputed')"
           )
  end
end
