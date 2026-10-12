# frozen_string_literal: true

require "test_helper"

module Team
  class RejectRoleChangeTest < ActiveSupport::TestCase
    setup do
      @requester = create(:internal_staff_user)
      @rejector  = create(:internal_staff_user)
      @target    = create(:merchant_user)
      @request   = create(:role_assignment_request,
                          target_user:  @target,
                          requested_by: @requester,
                          status:       "pending")
    end

    test "returns failure when the request is not pending" do
      @request.update!(status: "rejected", reviewed_by: @rejector, reviewed_at: Time.current)
      result = call
      refute result.success?
      assert_match "already been decided", result.error
    end

    test "returns failure when rejector is the same as the requester" do
      result = reject_by(@requester)
      refute result.success?
      assert_match "cannot reject a request you submitted", result.error
    end

    test "marks the request as rejected" do
      call
      assert @request.reload.rejected?
    end

    test "records the rejector and reviewed_at" do
      freeze_time do
        call
        req = @request.reload
        assert_equal @rejector,    req.reviewed_by
        assert_equal Time.current, req.reviewed_at
      end
    end

    test "stores the rejection reason when provided" do
      reject_by(@rejector, reason: "Violates access policy")
      assert_equal "Violates access policy", @request.reload.rejection_reason
    end

    test "stores nil rejection_reason when reason is blank" do
      reject_by(@rejector, reason: "")
      assert_nil @request.reload.rejection_reason
    end

    test "writes an audit log on success" do
      assert_difference "AuditLog.count", 1 do
        call
      end
      assert_equal "team.role_change_rejected", AuditLog.last.action
      assert_equal "succeeded",                 AuditLog.last.outcome
    end

    test "does not modify any user roles" do
      assert_no_difference "UserRole.count" do
        call
      end
    end

    private

    def call                      = reject_by(@rejector)
    def reject_by(u, reason: nil) = Team::RejectRoleChange.new(request: @request, rejected_by: u, reason: reason).call
  end
end
