defmodule YagyeCore.Repo.Migrations.AddSodToPlatformFeeInvoices do
  use Ecto.Migration

  def change do
    alter table(:platform_fee_invoices) do
      add :write_off_initiated_by, :text
      add :write_off_approved_by, :text
    end

    execute(
      """
      ALTER TABLE platform_fee_invoices
        ADD CONSTRAINT platform_fee_invoices_write_off_sod
        CHECK (
          write_off_approved_by IS NULL OR
          write_off_initiated_by IS NULL OR
          write_off_approved_by <> write_off_initiated_by
        )
      """,
      "ALTER TABLE platform_fee_invoices DROP CONSTRAINT platform_fee_invoices_write_off_sod"
    )
  end
end
