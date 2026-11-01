defmodule YagyeCore.Repo.Migrations.CreateSplitPayoutTables do
  use Ecto.Migration

  def change do
    create table(:split_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :public_id, :string, null: false

      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false

      add :name, :string, null: false
      add :description, :text
      add :mode, :string, null: false
      add :active, :boolean, null: false, default: true

      add :metadata, :map, default: %{}

      timestamps(inserted_at: :inserted_at, updated_at: :updated_at, type: :utc_datetime_usec)
    end

    create unique_index(:split_rules, [:public_id])
    create index(:split_rules, [:merchant_id])
    create index(:split_rules, [:merchant_id, :active])

    create constraint(:split_rules, :valid_mode, check: "mode IN ('simulation','sandbox','live')")

    create table(:split_rule_legs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :public_id, :string, null: false

      add :split_rule_id,
          references(:split_rules, type: :uuid, on_delete: :restrict),
          null: false

      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false

      add :label, :string, null: false
      add :split_type, :string, null: false
      add :value, :bigint, null: false
      add :rank, :integer, null: false, default: 0

      add :metadata, :map, default: %{}

      timestamps(inserted_at: :inserted_at, updated_at: :updated_at, type: :utc_datetime_usec)
    end

    create unique_index(:split_rule_legs, [:public_id])
    create index(:split_rule_legs, [:split_rule_id])

    create constraint(:split_rule_legs, :valid_split_type,
             check: "split_type IN ('percentage','flat')"
           )

    create constraint(:split_rule_legs, :positive_value, check: "value > 0")

    alter table(:payments) do
      add :split_rule_id, references(:split_rules, type: :uuid, on_delete: :restrict)
    end

    create table(:split_records, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :public_id, :string, null: false

      add :payment_id, references(:payments, type: :uuid, on_delete: :restrict), null: false

      add :split_rule_id,
          references(:split_rules, type: :uuid, on_delete: :restrict),
          null: false

      add :split_rule_leg_id,
          references(:split_rule_legs, type: :uuid, on_delete: :restrict),
          null: false

      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false

      add :amount, :bigint, null: false
      add :currency, :string, null: false, size: 3
      add :mode, :string, null: false
      add :state, :string, null: false, default: "pending"

      add :settled_at, :utc_datetime_usec

      add :metadata, :map, default: %{}

      timestamps(inserted_at: :inserted_at, updated_at: :updated_at, type: :utc_datetime_usec)
    end

    create unique_index(:split_records, [:public_id])
    create index(:split_records, [:payment_id])
    create index(:split_records, [:split_rule_id])
    create index(:split_records, [:merchant_id])
    create index(:split_records, [:state])

    create constraint(:split_records, :valid_state,
             check: "state IN ('pending','settled','failed')"
           )

    create constraint(:split_records, :positive_amount, check: "amount > 0")
  end
end
