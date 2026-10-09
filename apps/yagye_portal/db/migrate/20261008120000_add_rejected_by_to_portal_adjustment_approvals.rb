class AddRejectedByToPortalAdjustmentApprovals < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_adjustment_approvals, :rejected_by, :text
    add_column :portal_adjustment_approvals, :rejected_at, :datetime
  end
end
