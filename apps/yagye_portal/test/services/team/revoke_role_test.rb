# frozen_string_literal: true

require "test_helper"

module Team
  class RevokeRoleTest < ActiveSupport::TestCase
    setup do
      @revoker  = create(:internal_staff_user)
      @merchant = create(:merchant_user)
      @role_key = "merchant_finance"
    end

    test "returns failure when the user does not hold the role" do
      result = call

      refute result.success?
      assert_equal "Active role assignment not found", result.error
    end

    test "failure is recorded in the audit log" do
      assert_difference "AuditLog.count", 1 do
        call
      end

      log = AuditLog.last
      assert_equal "team.role_revoked", log.action
      assert_equal "failed",            log.outcome
    end

    test "sets revoked_at on the UserRole" do
      user_role = create(:user_role, user: @merchant, role_key: @role_key,
                                     merchant_code: @merchant.merchant_code)

      freeze_time do
        result = call
        assert result.success?
        assert_equal Time.current, user_role.reload.revoked_at
      end
    end

    test "revoked role is removed from UserRole.active" do
      user_role = create(:user_role, user: @merchant, role_key: @role_key,
                                     merchant_code: @merchant.merchant_code)
      call
      refute_includes UserRole.active, user_role
    end

    test "successful revocation is recorded in the audit log" do
      create(:user_role, user: @merchant, role_key: @role_key,
                         merchant_code: @merchant.merchant_code)

      assert_difference "AuditLog.count", 1 do
        call
      end

      log = AuditLog.last
      assert_equal "team.role_revoked", log.action
      assert_equal "succeeded",         log.outcome
    end

    private

    def call
      Team::RevokeRole.new(
        user:       @merchant,
        role_key:   @role_key,
        revoked_by: @revoker
      ).call
    end
  end
end
