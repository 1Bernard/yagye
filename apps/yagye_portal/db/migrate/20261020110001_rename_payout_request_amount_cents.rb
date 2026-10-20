class RenamePayoutRequestAmountCents < ActiveRecord::Migration[8.0]
  def change
    rename_column :portal_payout_requests, :amount_cents, :amount
  end
end
