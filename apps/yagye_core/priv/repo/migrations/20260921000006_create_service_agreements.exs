defmodule YagyeCore.Repo.Migrations.CreateServiceAgreements do
  use Ecto.Migration

  def change do
    create table(:service_agreements, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :delete_all), null: false
      add :agreement_version, :string, null: false
      add :accepted_at, :utc_datetime_usec, null: false
      add :signatory_name, :string, null: false
      add :signatory_email, :string, null: false
      add :signatory_phone, :string
      add :signatory_job_title, :string
      add :ip_address, :string
      add :user_agent, :text

      timestamps(type: :utc_datetime_usec, inserted_at: :inserted_at, updated_at: false)
    end
  end
end
