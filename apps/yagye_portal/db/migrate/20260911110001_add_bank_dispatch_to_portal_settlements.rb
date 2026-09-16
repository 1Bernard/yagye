class AddBankDispatchToPortalSettlements < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_settlements, :bank_dispatch_ref, :string
    add_column :portal_settlements, :bank_dispatched_at, :datetime
  end
end
