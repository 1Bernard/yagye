# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  # ── Predicates ──────────────────────────────────────────────────────────────

  test "internal_staff? is true for internal_staff kind" do
    user = build(:internal_staff_user)
    assert user.internal_staff?
    refute user.merchant_user?
  end

  test "merchant_user? is true for merchant_user kind" do
    user = build(:merchant_user)
    assert user.merchant_user?
    refute user.internal_staff?
  end

  # ── full_name ───────────────────────────────────────────────────────────────

  test "full_name concatenates first and last name" do
    user = build(:user, first_name: "Abena", last_name: "Mensah")
    assert_equal "Abena Mensah", user.full_name
  end

  test "full_name falls back to email when names are blank" do
    user = build(:user, first_name: nil, last_name: nil)
    assert_equal user.email, user.full_name
  end

  # ── merchant_code ───────────────────────────────────────────────────────────

  test "merchant_code returns the code from the active membership" do
    user       = create(:merchant_user)
    membership = user.active_membership
    assert_equal membership.merchant_code, user.merchant_code
  end

  test "merchant_code is nil for internal_staff with no membership" do
    user = create(:internal_staff_user)
    assert_nil user.merchant_code
  end

  # ── permitted? ─────────────────────────────────────────────────────────────

  test "permitted? returns true for a permission granted via the user's role" do
    user = create(:user_role, :ops_analyst).user
    # ops_analyst is seeded with payments.view
    assert user.permitted?("payments.view")
  end

  test "permitted? returns false for a permission not in the user's role" do
    user = create(:user_role, :ops_analyst).user
    # ops_analyst does not have platform_finance.view
    refute user.permitted?("platform_finance.view")
  end

  test "permitted? returns false when the user has no roles" do
    user = create(:merchant_user)
    refute user.permitted?("payments.view")
  end

  test "permitted? populates Current.permissions on first call" do
    user = create(:user_role).user  # merchant_owner

    assert_nil Current.permissions
    user.permitted?("payments.view")
    assert_instance_of Set, Current.permissions
    assert Current.permissions.include?("payments.view")
    assert Current.permissions.include?("payments.export")
  end

  # ── merchant_tier ───────────────────────────────────────────────────────────

  test "merchant_tier returns nil for internal_staff" do
    user = create(:internal_staff_user)
    assert_nil user.merchant_tier
  end

  test "merchant_tier returns 1 when no KYB application exists" do
    user = create(:merchant_user)
    assert_equal 1, user.merchant_tier
  end

  test "merchant_tier returns 2 for submitted application" do
    user = create(:merchant_user)
    create(:portal_merchant_application, merchant_code: user.merchant_code, status: "submitted")
    assert_equal 2, user.merchant_tier
  end

  test "merchant_tier returns 2 for under_review application" do
    user = create(:merchant_user)
    create(:portal_merchant_application, merchant_code: user.merchant_code, status: "under_review")
    assert_equal 2, user.merchant_tier
  end

  test "merchant_tier returns 3 for approved application" do
    user = create(:merchant_user)
    create(:portal_merchant_application, merchant_code: user.merchant_code, status: "approved")
    assert_equal 3, user.merchant_tier
  end
end
