# frozen_string_literal: true

require "test_helper"

module Team
  class ApproveRoleChangeTest < ActiveSupport::TestCase
    setup do
      @requester = create(:internal_staff_user)
      @approver  = create(:internal_staff_user)
      @target    = create(:merchant_user)
      create(:user_role, user: @target, role_key: "merchant_finance",
             merchant_code: @target.merchant_code)
      @request = create(:role_assignment_request,
                        target_user:         @target,
                        requested_by:        @requester,
                        current_role_keys:   [ "merchant_finance" ],
                        requested_role_keys: [ "merchant_owner" ],
                        status:              "pending")
    end

    test "returns failure when the request is not pending" do
      @request.update!(status: "approved", reviewed_by: @approver, reviewed_at: Time.current)
      result = call
      refute result.success?
      assert_match "already been decided", result.error
    end

    test "returns failure when approver is the same as the requester" do
      result = approve_by(@requester)
      refute result.success?
      assert_match "cannot approve a request you submitted", result.error
    end

    test "assigns the requested role to the target user" do
      call
      assert UserRole.active.exists?(user: @target, role_key: "merchant_owner")
    end

    test "revokes the previous role from the target user" do
      call
      refute UserRole.active.exists?(user: @target, role_key: "merchant_finance")
    end

    test "marks the request as approved" do
      call
      assert @request.reload.approved?
    end

    test "records the approver and reviewed_at on the request" do
      freeze_time do
        call
        req = @request.reload
        assert_equal @approver,    req.reviewed_by
        assert_equal Time.current, req.reviewed_at
      end
    end

    test "writes an audit log on success" do
      # RevokeRole also writes one audit entry; the approve entry is the final one
      call
      approve_log = AuditLog.where(action: "team.role_change_approved").last
      assert_not_nil approve_log
      assert_equal "succeeded", approve_log.outcome
    end

    test "is a no-op if requested and current role are already the same" do
      @request.update!(current_role_keys: [ "merchant_owner" ],
                       requested_role_keys: [ "merchant_owner" ])
      create(:user_role, user: @target, role_key: "merchant_owner",
             merchant_code: @target.merchant_code)

      assert_no_difference "UserRole.count" do
        call
      end
      assert @request.reload.approved?
    end

    private

    def call          = approve_by(@approver)
    def approve_by(u) = Team::ApproveRoleChange.new(request: @request, approved_by: u).call
  end
end
