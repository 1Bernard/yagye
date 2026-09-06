class CreateRoleAssignmentRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :role_assignment_requests, id: :uuid do |t|
      t.references :target_user,   null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :requested_by,  null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :reviewed_by,   null: true,  foreign_key: { to_table: :users }, type: :uuid
      t.string  :current_role_keys,   array: true, default: [], null: false
      t.string  :requested_role_keys, array: true, default: [], null: false
      t.string  :status, null: false, default: "pending"
      t.timestamptz :reviewed_at
      t.text :rejection_reason
      t.timestamps
    end

    add_index :role_assignment_requests, :status
    add_index :role_assignment_requests, [ :target_user_id, :status ]

    # SoD constraints — enforced at DB level
    execute <<~SQL
      ALTER TABLE role_assignment_requests
        ADD CONSTRAINT no_self_request
          CHECK (target_user_id != requested_by_id);

      ALTER TABLE role_assignment_requests
        ADD CONSTRAINT no_self_approve
          CHECK (reviewed_by_id IS NULL OR reviewed_by_id != requested_by_id);

      ALTER TABLE role_assignment_requests
        ADD CONSTRAINT valid_status
          CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'));
    SQL
  end
end
