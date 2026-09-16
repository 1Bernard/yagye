defmodule YagyeCore.Repo.Migrations.CreateMerchantSettlementControls do
  use Ecto.Migration

  def change do
    create table(:merchant_settlement_controls, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all), null: false
      add :approval_threshold, :integer
      add :approver_user_codes, {:array, :text}, null: false, default: []
      add :updated_by, :text

      timestamps(type: :utc_datetime_usec, inserted_at: :inserted_at, updated_at: :updated_at)
    end

    create unique_index(:merchant_settlement_controls, [:merchant_id])
  end
end
