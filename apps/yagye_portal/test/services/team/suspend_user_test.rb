# frozen_string_literal: true

require "test_helper"

module Team
  class SuspendUserTest < ActiveSupport::TestCase
    setup do
      @suspender = create(:internal_staff_user)
      @target    = create(:merchant_user)
    end

    test "returns failure when the user attempts to suspend themselves" do
      result = call(user: @suspender, suspended_by: @suspender)

      refute result.success?
      assert_equal "You cannot suspend yourself", result.error
    end

    test "self-suspension attempt is recorded in the audit log" do
      assert_difference "AuditLog.count", 1 do
        call(user: @suspender, suspended_by: @suspender)
      end

      log = AuditLog.last
      assert_equal "team.user_suspended", log.action
      assert_equal "failed",              log.outcome
    end

    test "locks access on the target user" do
      call(user: @target, suspended_by: @suspender)

      assert @target.reload.access_locked?
    end

    test "transitions the active membership to suspended state" do
      membership = @target.active_membership
      call(user: @target, suspended_by: @suspender)
      assert_equal "suspended", membership.reload.state
    end

    test "suspended user no longer has an active membership" do
      call(user: @target, suspended_by: @suspender)
      assert_nil @target.reload.active_membership
    end

    test "successful suspension is recorded in the audit log" do
      assert_difference "AuditLog.count", 1 do
        call(user: @target, suspended_by: @suspender)
      end

      log = AuditLog.last
      assert_equal "team.user_suspended", log.action
      assert_equal "succeeded",           log.outcome
    end

    test "one user suspending another merchant user" do
      owner  = create(:merchant_user)
      target = create(:merchant_user)

      result = call(user: target, suspended_by: owner)

      assert result.success?
      assert target.reload.access_locked?
    end

    private

    def call(user:, suspended_by:)
      Team::SuspendUser.new(user: user, suspended_by: suspended_by).call
    end
  end
end
