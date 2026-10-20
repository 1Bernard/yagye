# frozen_string_literal: true

class AddRequestCodeToPortalPayoutRequests < ActiveRecord::Migration[8.0]
  def up
    add_column :portal_payout_requests, :request_code, :string

    PortalPayoutRequest.reset_column_information
    PortalPayoutRequest.find_each do |r|
      r.update_column(:request_code, "prq_#{SecureRandom.hex(8)}")
    end

    change_column_null :portal_payout_requests, :request_code, false
    add_index :portal_payout_requests, :request_code, unique: true
  end

  def down
    remove_index :portal_payout_requests, :request_code
    remove_column :portal_payout_requests, :request_code
  end
end
