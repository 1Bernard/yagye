class RenameAmountCentsToAmount < ActiveRecord::Migration[8.0]
  def change
    rename_column :portal_payments, :amount_cents, :amount
    rename_column :portal_disputes, :amount_cents, :amount
  end
end
