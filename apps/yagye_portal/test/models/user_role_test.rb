# frozen_string_literal: true

require "test_helper"

class UserRoleTest < ActiveSupport::TestCase
  # ── .active scope ──────────────────────────────────────────────────────────

  test "active scope includes unrevoked roles with no expiry" do
    ur = create(:user_role)
    assert_includes UserRole.active, ur
  end

  test "active scope excludes revoked roles" do
    ur = create(:user_role, revoked_at: 1.hour.ago)
    refute_includes UserRole.active, ur
  end

  test "active scope excludes roles past their expires_at" do
    ur = create(:user_role, expires_at: 1.hour.ago)
    refute_includes UserRole.active, ur
  end

  test "active scope includes roles with a future expires_at" do
    ur = create(:user_role, expires_at: 1.year.from_now)
    assert_includes UserRole.active, ur
  end

  # ── Scope validation ────────────────────────────────────────────────────────

  test "merchant role cannot be assigned to internal_staff" do
    staff = create(:internal_staff_user)
    ur    = build(:user_role, user: staff, role_key: "merchant_owner")
    refute ur.valid?
    assert_includes ur.errors[:role_key], "is a merchant role but user is internal_staff"
  end

  test "internal role cannot be assigned to merchant_user" do
    merchant = create(:merchant_user)
    ur       = build(:user_role, user: merchant, role_key: "ops_analyst",
                                 merchant_code: nil)
    refute ur.valid?
    assert_includes ur.errors[:role_key], "is an internal role but user is merchant_user"
  end

  test "merchant role can be assigned to merchant_user" do
    ur = build(:user_role)  # defaults to merchant_owner + merchant_user
    assert ur.valid?
  end

  test "internal role can be assigned to internal_staff" do
    ur = build(:user_role, :ops_analyst)
    assert ur.valid?
  end

  # ── #revoke! ───────────────────────────────────────────────────────────────

  test "revoke! sets revoked_at to now" do
    ur = create(:user_role)
    freeze_time do
      ur.revoke!
      assert_equal Time.current, ur.reload.revoked_at
    end
  end

  test "revoke! removes the role from the active scope" do
    ur = create(:user_role)
    ur.revoke!
    refute_includes UserRole.active, ur
  end
end
