defmodule YagyeCore.Repo.Migrations.CreateMerchantAddresses do
  use Ecto.Migration

  def change do
    create table(:merchant_addresses, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all), null: false
      add :country, :string, size: 2
      add :region, :string
      add :city, :string
      add :street_address, :string
      add :gps_address, :string
      add :complex_building, :string
      add :address_type, :string, null: false, default: "office"

      timestamps(type: :utc_datetime_usec, inserted_at: :inserted_at, updated_at: :updated_at)
    end

    create unique_index(:merchant_addresses, [:merchant_id, :address_type])
  end
end
