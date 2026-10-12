defmodule YagyeCore.Repo.Migrations.AddSecretNameToProviderCredentials do
  use Ecto.Migration

  def change do
    alter table(:provider_credentials) do
      add :secret_name, :string
    end

    # encrypted_payload now nullable — rows backed by Secrets Manager have a
    # secret_name instead. Existing rows keep their encrypted_payload unchanged.
    alter table(:provider_credentials) do
      modify :encrypted_payload, :binary, null: true
    end
  end
end
