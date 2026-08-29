class CreatePortalMerchantApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_merchant_applications, id: false do |t|
      t.text    :application_code, primary_key: true, null: false
      t.integer :aggregate_version, null: false, default: 0
      t.text    :status, null: false
      t.text    :legal_name, null: false
      t.text    :trading_name
      t.string  :country, limit: 2, null: false
      t.text    :industry
      t.text    :employee_range
      t.text    :submitted_by_email
      t.text    :reviewed_by
      t.text    :approved_by
      t.text    :rejected_reason
      t.text    :merchant_code
      t.text    :last_event_id, null: false
      t.timestamptz :last_applied_at, null: false
    end

    add_index :portal_merchant_applications, :status
    add_index :portal_merchant_applications, :merchant_code
  end
end
