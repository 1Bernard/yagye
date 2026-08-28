class CreatePortalRbac < ActiveRecord::Migration[8.1]
  def up
    # ── Update users: add kind + user_code, drop placeholder columns ──────────
    add_column :users, :user_code, :text
    add_column :users, :kind, :text, null: false, default: "merchant_user"

    add_index :users, :user_code, unique: true
    execute "ALTER TABLE users ADD CONSTRAINT valid_user_kind CHECK (kind IN ('merchant_user', 'internal_staff'))"

    # ── Roles ─────────────────────────────────────────────────────────────────
    create_table :roles, id: false do |t|
      t.text :key, primary_key: true
      t.text :name, null: false
      t.text :scope, null: false
      t.text :description, null: false
      t.boolean :system_role, null: false, default: true
      t.timestamps
    end

    execute "ALTER TABLE roles ADD CONSTRAINT valid_role_scope CHECK (scope IN ('merchant', 'internal'))"

    # ── Permissions ───────────────────────────────────────────────────────────
    create_table :permissions, id: false do |t|
      t.text :key, primary_key: true
      t.text :resource, null: false
      t.text :action, null: false
      t.text :description, null: false
      t.datetime :created_at, null: false
    end

    # ── Grant matrix ──────────────────────────────────────────────────────────
    create_table :role_permissions, primary_key: [ :role_key, :permission_key ] do |t|
      t.text :role_key, null: false
      t.text :permission_key, null: false
      t.datetime :granted_at, null: false
    end

    add_foreign_key :role_permissions, :roles, column: :role_key, primary_key: :key
    add_foreign_key :role_permissions, :permissions, column: :permission_key, primary_key: :key

    # ── User → Role assignments ───────────────────────────────────────────────
    create_table :user_roles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :role_key, null: false
      t.text :merchant_code
      t.references :granted_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :granted_at, null: false
      t.datetime :expires_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_foreign_key :user_roles, :roles, column: :role_key, primary_key: :key
    add_index :user_roles, [ :user_id, :role_key, :merchant_code ],
              unique: true, where: "revoked_at IS NULL",
              name: :user_roles_active_unique

    # ── Merchant memberships ──────────────────────────────────────────────────
    create_table :merchant_memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :merchant_code, null: false
      t.text :merchant_name, null: false
      t.text :state, null: false, default: "invited"
      t.references :invited_by, foreign_key: { to_table: :users }, type: :uuid
      t.text :invitation_token_digest
      t.datetime :invitation_expires_at
      t.datetime :accepted_at
      t.timestamps
    end

    execute "ALTER TABLE merchant_memberships ADD CONSTRAINT valid_membership_state CHECK (state IN ('invited', 'active', 'suspended', 'removed'))"
    add_index :merchant_memberships, [ :user_id, :merchant_code ],
              unique: true, where: "state = 'active'",
              name: :merchant_memberships_one_active_per_user
  end

  def down
    drop_table :merchant_memberships
    drop_table :user_roles
    remove_foreign_key :role_permissions, :roles
    remove_foreign_key :role_permissions, :permissions
    drop_table :role_permissions
    drop_table :permissions
    drop_table :roles
    remove_index :users, :user_code
    execute "ALTER TABLE users DROP CONSTRAINT valid_user_kind"
    remove_column :users, :kind
    remove_column :users, :user_code
  end
end
