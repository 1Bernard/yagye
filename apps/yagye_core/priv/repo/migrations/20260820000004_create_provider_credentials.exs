defmodule YagyeCore.Repo.Migrations.CreateProviderCredentials do
  use Ecto.Migration

  def change do
    create table(:provider_credentials, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :provider_id, references(:providers, type: :uuid, on_delete: :restrict), null: false
      # NULL = platform-level credential; non-NULL = merchant brings their own account (Model B)
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict)
      add :mode, :text, null: false
      # Provider base URL stored here so adapters use it from the credential, not hardcoded config
      add :base_url, :text, null: false
      # AES-256-GCM envelope. Contains api_key, secret, and any provider-specific fields.
      add :encrypted_payload, :binary, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at, inserted_at: :inserted_at)
    end

    create constraint(:provider_credentials, :valid_mode,
      check: "mode IN ('simulation','sandbox','live')"
    )

    create unique_index(:provider_credentials, [:provider_id, :merchant_id, :mode])
  end
end
