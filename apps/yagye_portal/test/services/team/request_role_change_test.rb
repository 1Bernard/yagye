# frozen_string_literal: true

require "test_helper"

module Team
  class RequestRoleChangeTest < ActiveSupport::TestCase
    setup do
      @manager  = create(:internal_staff_user)
      @merchant = create(:merchant_user)
      create(:user_role, user: @merchant, role_key: "merchant_finance",
             merchant_code: @merchant.merchant_code)
    end

    test "returns failure when target and requester are the same user" do
      result = call(target_user: @manager, requested_by: @manager,
                    requested_key: "merchant_owner", current_keys: [])
      refute result.success?
      assert_match "cannot modify your own roles", result.error
    end

    test "returns failure when the role selection has not changed" do
      result = call(requested_key: "merchant_finance", current_keys: [ "merchant_finance" ])
      refute result.success?
      assert_match "No changes", result.error
    end

    test "returns failure when a pending request already exists for the user" do
      create(:role_assignment_request, target_user: @merchant, requested_by: @manager)
      result = call(requested_key: "merchant_owner", current_keys: [ "merchant_finance" ])
      refute result.success?
      assert_match "already awaiting approval", result.error
    end

    test "creates a RoleAssignmentRequest on success" do
      assert_difference "RoleAssignmentRequest.count", 1 do
        result = call(requested_key: "merchant_owner", current_keys: [ "merchant_finance" ])
        assert result.success?
      end
    end

    test "persisted request has correct role keys" do
      call(requested_key: "merchant_owner", current_keys: [ "merchant_finance" ])
      req = RoleAssignmentRequest.last
      assert_equal [ "merchant_finance" ], req.current_role_keys
      assert_equal [ "merchant_owner" ],   req.requested_role_keys
    end

    test "persisted request is pending" do
      call(requested_key: "merchant_owner", current_keys: [ "merchant_finance" ])
      assert RoleAssignmentRequest.last.pending?
    end

    test "writes an audit log on success" do
      assert_difference "AuditLog.count", 1 do
        call(requested_key: "merchant_owner", current_keys: [ "merchant_finance" ])
      end
      assert_equal "team.role_change_requested", AuditLog.last.action
    end

    test "does not write an audit log on failure" do
      assert_no_difference "AuditLog.count" do
        call(requested_key: "merchant_finance", current_keys: [ "merchant_finance" ])
      end
    end

    test "request keys are sorted so order does not affect no_change detection" do
      result = call(
        requested_key: "merchant_finance",
        current_keys:  [ "merchant_finance" ]
      )
      refute result.success?
      assert_match "No changes", result.error
    end

    private

    def call(target_user: @merchant, requested_by: @manager,
             requested_key:, current_keys:)
      Team::RequestRoleChange.new(
        target_user:    target_user,
        requested_by:   requested_by,
        requested_keys: [ requested_key ],
        current_keys:   current_keys
      ).call
    end
  end
end
