# frozen_string_literal: true

class CreatePortalNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :portal_notifications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user,       null: false, foreign_key: true, type: :uuid
      t.string     :event_type, null: false
      t.string     :title,      null: false
      t.string     :body,       null: false
      t.string     :link
      t.jsonb      :metadata,   null: false, default: {}
      t.datetime   :read_at

      t.timestamps
    end

    add_index :portal_notifications, [ :user_id, :read_at ]
    add_index :portal_notifications, [ :user_id, :created_at ]
  end
end
