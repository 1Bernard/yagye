defmodule YagyeCore.Repo.Migrations.AddRefundedAmountToPayments do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      # Running total of all refund amounts that have reached requested or succeeded state.
      # Incremented atomically within the refund creation transaction.
      # Enforces: SUM(refunds.amount WHERE state IN [requested, succeeded]) <= payment.amount
      add :refunded_amount, :integer, default: 0, null: false
    end

    create constraint(:payments, :refunded_amount_non_negative, check: "refunded_amount >= 0")

    create constraint(:payments, :refunded_amount_not_exceeds_original,
             check: "refunded_amount <= amount"
           )
  end
end
