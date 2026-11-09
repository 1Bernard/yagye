# frozen_string_literal: true

class AddRiskFieldsToPortalPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_payments, :risk_decision,   :text
    add_column :portal_payments, :risk_score,      :float
    add_column :portal_payments, :risk_flagged_at, :datetime

    add_index :portal_payments, :risk_decision
  end
end
