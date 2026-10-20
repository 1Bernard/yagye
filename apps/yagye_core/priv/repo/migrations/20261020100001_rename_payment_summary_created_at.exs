defmodule YagyeCore.Repo.Migrations.RenamePaymentSummaryCreatedAt do
  use Ecto.Migration

  # `created_at` was a misleading name — it shadowed the DB insertion timestamp convention.
  # The field stores when the payment domain event occurred (the business timestamp), not
  # when the projection row was written. `payment_initiated_at` makes this unambiguous.
  def change do
    rename table(:proj_payment_summaries), :created_at, to: :payment_initiated_at
  end
end
