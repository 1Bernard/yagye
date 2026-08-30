# frozen_string_literal: true

require "test_helper"

module Team
  class InviteUserTest < ActiveSupport::TestCase
    setup do
      @inviter       = create(:merchant_user)
      @merchant_code = @inviter.merchant_code
      @merchant_name = @inviter.active_membership.merchant_name
    end

    test "returns failure when the role key does not exist" do
      result = call(role_key: "ghost_role")

      refute result.success?
      assert_equal "Role 'ghost_role' not found", result.error
    end

    test "merchant user cannot invite with an internal role" do
      result = call(role_key: "ops_analyst")

      refute result.success?
      assert_equal "Merchant users cannot assign internal roles", result.error
    end

    test "creates User, UserRole, and MerchantMembership in one transaction" do
      assert_difference(
        "User.count"              => 1,
        "UserRole.count"          => 1,
        "MerchantMembership.count" => 1
      ) do
        result = call
        assert result.success?
        assert_kind_of User, result.user
        assert_equal "merchant_owner", result.user.user_roles.first.role_key
      end
    end

    test "new user's email is normalised to lowercase" do
      result = call(email: "  NEWPERSON@Example.COM  ")
      assert_equal "newperson@example.com", result.user.email
    end

    test "membership is created with invited state" do
      result = call
      membership = result.user.merchant_memberships.first
      assert_equal "invited",        membership.state
      assert_equal @merchant_code,   membership.merchant_code
      assert_in_delta 7.days.from_now, membership.invitation_expires_at, 5.seconds
    end

    test "duplicating an existing email rolls back all three records" do
      existing_email = "existing@example.com"
      create(:user, email: existing_email)

      assert_no_difference([ "User.count", "UserRole.count", "MerchantMembership.count" ]) do
        result = call(email: existing_email)
        refute result.success?
        assert result.error.present?
      end
    end

    test "successful invite is recorded in the audit log" do
      assert_difference "AuditLog.count", 1 do
        call
      end

      log = AuditLog.last
      assert_equal "team.user_invited", log.action
      assert_equal "succeeded",         log.outcome
      assert_equal @merchant_code,      log.merchant_code
    end

    private

    def call(email: "newmember@example.com", role_key: "merchant_owner")
      Team::InviteUser.new(
        email:         email,
        first_name:    "New",
        last_name:     "Member",
        role_key:      role_key,
        merchant_code: @merchant_code,
        merchant_name: @merchant_name,
        invited_by:    @inviter
      ).call
    end
  end
end
