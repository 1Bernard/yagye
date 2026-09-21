defmodule YagyeCore.Repo.Migrations.CreateMerchantContacts do
  use Ecto.Migration

  def change do
    create table(:merchant_contacts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all), null: false
      add :general_email, :string
      add :support_email, :string
      add :disputes_email, :string
      add :phone_number, :string
      add :whatsapp_number, :string
      add :whatsapp_label, :string
      add :website_url, :string
      add :twitter_handle, :string
      add :facebook_username, :string
      add :instagram_handle, :string

      timestamps(type: :utc_datetime_usec, inserted_at: :inserted_at, updated_at: :updated_at)
    end

    create unique_index(:merchant_contacts, [:merchant_id])
  end
end
