# frozen_string_literal: true

class AddSettlementApprovalToPortalSettlements < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_settlements, :dispatch_approved_by,      :string
    add_column :portal_settlements, :dispatch_rejected_by,      :string
    add_column :portal_settlements, :dispatch_rejection_reason, :string
  end
end
