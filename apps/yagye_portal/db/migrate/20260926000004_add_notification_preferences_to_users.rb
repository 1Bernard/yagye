# frozen_string_literal: true

class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.0]
  DEFAULT_PREFS = {
    "events" => {
      "payment_success"  => true,
      "payment_failed"   => true,
      "dispute_opened"   => true,
      "dispute_resolved" => true,
      "kyb_status"       => true,
      "new_team_member"  => false,
      "api_key_created"  => false,
      "login_new_device" => true
    },
    "channels" => {
      "email"  => true,
      "in_app" => true
    }
  }.to_json.freeze

  def change
    add_column :users, :notification_preferences, :jsonb,
               null: false, default: DEFAULT_PREFS
  end
end
