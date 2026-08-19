defmodule YagyeCore.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    # ── payments ────────────────────────────────────────────────────────────
    create table(:payments, primary_key: false) do
      add :id,                 :uuid,    primary_key: true, default: fragment("gen_random_uuid()")
      add :public_id,          :text,    null: false
      add :merchant_id,        references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode,               :text,    null: false
      add :amount,             :bigint,  null: false
      add :currency,           :char,    size: 3, null: false
      add :state,              :text,    null: false, default: "created"
      add :rail,               :text,    null: false
      add :method,             :text
      add :merchant_reference, :text
      add :description,        :text
      add :version,            :integer, null: false, default: 0
      add :metadata,           :jsonb,   null: false, default: "{}"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payments, [:public_id])
    create unique_index(:payments, [:merchant_id, :merchant_reference],
      where: "merchant_reference IS NOT NULL"
    )
    create index(:payments, [:merchant_id, :inserted_at])
    create index(:payments, [:state, :updated_at])

    create constraint(:payments, :valid_state,
      check: "state IN ('created','processing','requires_action','authorised','succeeded','failed','cancelled','indeterminate')"
    )
    create constraint(:payments, :valid_rail,
      check: "rail IN ('fiat_provider','internal')"
    )
    create constraint(:payments, :valid_mode,
      check: "mode IN ('simulation','live')"
    )
    create constraint(:payments, :positive_amount,
      check: "amount > 0"
    )

    # ── payment_events ───────────────────────────────────────────────────────
    create table(:payment_events, primary_key: false) do
      add :id,             :uuid,  primary_key: true, default: fragment("gen_random_uuid()")
      add :payment_id,     references(:payments, type: :uuid, on_delete: :restrict), null: false
      add :version,        :integer, null: false
      add :event_type,     :text,    null: false
      add :from_state,     :text
      add :to_state,       :text
      add :payload,        :jsonb,   null: false, default: "{}"
      add :actor,          :text,    null: false
      add :correlation_id, :text,    null: false
      add :occurred_at,    :utc_datetime_usec, null: false
      add :recorded_at,    :utc_datetime_usec, null: false
    end

    create unique_index(:payment_events, [:payment_id, :version])
  end
end
