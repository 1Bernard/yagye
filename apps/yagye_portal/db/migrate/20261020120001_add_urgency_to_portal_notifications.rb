# frozen_string_literal: true

class AddUrgencyToPortalNotifications < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_notifications, :urgency, :string, null: false, default: "info"
    add_index  :portal_notifications, :urgency
  end
end
