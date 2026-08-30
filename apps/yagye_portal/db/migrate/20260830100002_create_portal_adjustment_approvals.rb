# frozen_string_literal: true

class CreatePortalAdjustmentApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_adjustment_approvals, id: :uuid do |t|
      t.uuid     :core_break_id,   null: false
      t.text     :proposed_by,     null: false
      t.datetime :proposed_at,     null: false
      t.jsonb    :proposed_action, null: false, default: {}
      t.text     :approved_by
      t.datetime :approved_at
      t.text     :rejected_reason
      t.text     :state,           null: false, default: "pending"
      t.text     :last_event_id
      t.timestamps null: false
    end
    add_index :portal_adjustment_approvals, :core_break_id, unique: true
    add_index :portal_adjustment_approvals, :state
  end
end
