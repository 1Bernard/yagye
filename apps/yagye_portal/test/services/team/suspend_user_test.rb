# frozen_string_literal: true

require "test_helper"

module Team
  class SuspendUserTest < ActiveSupport::TestCase
    setup do
      @suspender = create(:internal_staff_user)
      @merchant  = create(:merchant_user)
    end

    test "returns failure when user tries to suspend themselves" do
      result = call(user: @suspender, suspended_by: @suspender)
      refute result.success?
      assert_match "cannot suspend yourself", result.error
    end

    test "locks the user's devise access" do
      call
      assert @merchant.reload.access_locked?
    end

    test "sets the merchant membership state to suspended" do
      call
      assert_equal "suspended", @merchant.active_membership.reload.state
    end

    test "writes a succeeded audit log on success" do
      assert_difference "AuditLog.count", 1 do
        call
      end
      log = AuditLog.last
      assert_equal "team.user_suspended", log.action
      assert_equal "succeeded",           log.outcome
    end

    test "writes a failed audit log when user tries to suspend themselves" do
      assert_difference "AuditLog.count", 1 do
        call(user: @suspender, suspended_by: @suspender)
      end
      log = AuditLog.last
      assert_equal "team.user_suspended", log.action
      assert_equal "failed",              log.outcome
    end

    test "returns success" do
      result = call
      assert result.success?
    end

    private

    def call(user: @merchant, suspended_by: @suspender)
      Team::SuspendUser.new(user: user, suspended_by: suspended_by).call
    end
  end
end
