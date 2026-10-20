# frozen_string_literal: true

class AddSourceEventIdToPortalNotifications < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_notifications, :source_event_id, :string

    add_index :portal_notifications, [ :user_id, :source_event_id ],
              unique: true,
              where:  "source_event_id IS NOT NULL",
              name:   "idx_portal_notifs_on_user_source_event_id"
  end
end
