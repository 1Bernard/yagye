# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_29_100001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "merchant_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "invitation_expires_at"
    t.text "invitation_token_digest"
    t.uuid "invited_by_id"
    t.text "merchant_code", null: false
    t.text "merchant_name", null: false
    t.text "state", default: "invited", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["invited_by_id"], name: "index_merchant_memberships_on_invited_by_id"
    t.index ["user_id", "merchant_code"], name: "merchant_memberships_one_active_per_user", unique: true, where: "(state = 'active'::text)"
    t.index ["user_id"], name: "index_merchant_memberships_on_user_id"
    t.check_constraint "state = ANY (ARRAY['invited'::text, 'active'::text, 'suspended'::text, 'removed'::text])", name: "valid_membership_state"
  end

  create_table "permissions", primary_key: "key", id: :text, force: :cascade do |t|
    t.text "action", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.text "resource", null: false
  end

  create_table "portal_merchant_applications", primary_key: "application_code", id: :text, force: :cascade do |t|
    t.integer "aggregate_version", default: 0, null: false
    t.text "approved_by"
    t.string "country", limit: 2, null: false
    t.text "employee_range"
    t.text "industry"
    t.timestamptz "last_applied_at", null: false
    t.text "last_event_id", null: false
    t.text "legal_name", null: false
    t.text "merchant_code"
    t.text "rejected_reason"
    t.text "reviewed_by"
    t.text "status", null: false
    t.text "submitted_by_email"
    t.text "trading_name"
    t.index ["merchant_code"], name: "index_portal_merchant_applications_on_merchant_code"
    t.index ["status"], name: "index_portal_merchant_applications_on_status"
  end

  create_table "portal_payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.text "core_payment_id", null: false
    t.datetime "created_at", null: false
    t.text "currency", default: "GHS", null: false
    t.text "customer_email"
    t.text "customer_msisdn"
    t.text "description"
    t.text "merchant_code", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "paid_at"
    t.text "provider"
    t.text "reference"
    t.text "status", null: false
    t.datetime "updated_at", null: false
    t.index ["core_payment_id"], name: "index_portal_payments_on_core_payment_id", unique: true
    t.index ["merchant_code", "created_at"], name: "index_portal_payments_on_merchant_code_and_created_at"
    t.index ["merchant_code"], name: "index_portal_payments_on_merchant_code"
    t.index ["reference"], name: "index_portal_payments_on_reference"
    t.index ["status"], name: "index_portal_payments_on_status"
  end

  create_table "role_permissions", primary_key: ["role_key", "permission_key"], force: :cascade do |t|
    t.datetime "granted_at", null: false
    t.text "permission_key", null: false
    t.text "role_key", null: false
  end

  create_table "roles", primary_key: "key", id: :text, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.text "name", null: false
    t.text "scope", null: false
    t.boolean "system_role", default: true, null: false
    t.datetime "updated_at", null: false
    t.check_constraint "scope = ANY (ARRAY['merchant'::text, 'internal'::text])", name: "valid_role_scope"
  end

  create_table "user_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "granted_at", null: false
    t.uuid "granted_by_id"
    t.text "merchant_code"
    t.datetime "revoked_at"
    t.text "role_key", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["granted_by_id"], name: "index_user_roles_on_granted_by_id"
    t.index ["user_id", "role_key", "merchant_code"], name: "user_roles_active_unique", unique: true, where: "(revoked_at IS NULL)"
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "consumed_timestep"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.text "kind", default: "merchant_user", null: false
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.boolean "otp_required_for_login", default: false, null: false
    t.string "otp_secret"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.text "user_code"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["user_code"], name: "index_users_on_user_code", unique: true
    t.check_constraint "kind = ANY (ARRAY['merchant_user'::text, 'internal_staff'::text])", name: "valid_user_kind"
  end

  add_foreign_key "merchant_memberships", "users"
  add_foreign_key "merchant_memberships", "users", column: "invited_by_id"
  add_foreign_key "role_permissions", "permissions", column: "permission_key", primary_key: "key"
  add_foreign_key "role_permissions", "roles", column: "role_key", primary_key: "key"
  add_foreign_key "user_roles", "roles", column: "role_key", primary_key: "key"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_roles", "users", column: "granted_by_id"
end
