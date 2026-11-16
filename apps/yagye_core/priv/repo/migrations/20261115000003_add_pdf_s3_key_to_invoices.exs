defmodule YagyeCore.Repo.Migrations.AddPdfS3KeyToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :pdf_s3_key, :string
    end
  end
end
