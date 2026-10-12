# frozen_string_literal: true

require "test_helper"

class RoleAssignmentRequestTest < ActiveSupport::TestCase
  setup do
    @requester = create(:internal_staff_user)
    @approver  = create(:internal_staff_user)
    @target    = create(:merchant_user)
  end

  # ── Validations ───────────────────────────────────────────────────────────

  test "is invalid when target_user and requested_by are the same" do
    req = build(:role_assignment_request, target_user: @requester, requested_by: @requester)
    refute req.valid?
    assert_includes req.errors[:base], "Cannot request a role change for yourself"
  end

  test "is invalid when reviewed_by is the same as requested_by" do
    req = create(:role_assignment_request, requested_by: @requester, target_user: @target)
    req.reviewed_by = @requester
    refute req.valid?
    assert_includes req.errors[:base], "Requester and approver must be different people"
  end

  test "is valid with distinct requester and approver" do
    req = build(:role_assignment_request, requested_by: @requester,
                target_user: @target, reviewed_by: @approver)
    assert req.valid?
  end

  test "status must be a known value" do
    req = build(:role_assignment_request, status: "unknown")
    refute req.valid?
    assert req.errors[:status].any?
  end

  # ── Computed key diffs ────────────────────────────────────────────────────

  test "added_keys returns keys present in requested but not in current" do
    req = build(:role_assignment_request,
                current_role_keys:   [ "merchant_finance" ],
                requested_role_keys: [ "merchant_owner" ])
    assert_equal [ "merchant_owner" ], req.added_keys
  end

  test "removed_keys returns keys present in current but not in requested" do
    req = build(:role_assignment_request,
                current_role_keys:   [ "merchant_finance" ],
                requested_role_keys: [ "merchant_owner" ])
    assert_equal [ "merchant_finance" ], req.removed_keys
  end

  test "added_keys is empty when requested is a subset of current" do
    req = build(:role_assignment_request,
                current_role_keys:   [ "merchant_owner" ],
                requested_role_keys: [ "merchant_owner" ])
    assert_empty req.added_keys
  end

  test "no_change? is true when current and requested keys are identical" do
    req = build(:role_assignment_request,
                current_role_keys:   [ "merchant_owner" ],
                requested_role_keys: [ "merchant_owner" ])
    assert req.no_change?
  end

  test "no_change? is false when keys differ" do
    req = build(:role_assignment_request,
                current_role_keys:   [ "merchant_finance" ],
                requested_role_keys: [ "merchant_owner" ])
    refute req.no_change?
  end

  # ── Status predicates ────────────────────────────────────────────────────

  test "pending? is true for status=pending" do
    assert build(:role_assignment_request, status: "pending").pending?
  end

  test "approved? is true for status=approved" do
    assert build(:role_assignment_request, status: "approved").approved?
  end

  test "rejected? is true for status=rejected" do
    assert build(:role_assignment_request, status: "rejected").rejected?
  end

  test "cancelled? is true for status=cancelled" do
    assert build(:role_assignment_request, status: "cancelled").cancelled?
  end

  # ── Scopes ────────────────────────────────────────────────────────────────

  test "pending scope returns only pending requests" do
    pending_req  = create(:role_assignment_request, status: "pending",  target_user: @target, requested_by: @requester)
    approved_req = create(:role_assignment_request, status: "approved", target_user: create(:merchant_user), requested_by: @requester)
    assert_includes     RoleAssignmentRequest.pending, pending_req
    refute_includes     RoleAssignmentRequest.pending, approved_req
  end

  test "decided scope excludes pending requests" do
    pending_req  = create(:role_assignment_request, status: "pending",  target_user: @target, requested_by: @requester)
    rejected_req = create(:role_assignment_request, status: "rejected", target_user: create(:merchant_user), requested_by: @requester)
    refute_includes RoleAssignmentRequest.decided, pending_req
    assert_includes RoleAssignmentRequest.decided, rejected_req
  end

  test "for_user scope returns only requests for that user" do
    other = create(:merchant_user)
    req1  = create(:role_assignment_request, target_user: @target, requested_by: @requester)
    req2  = create(:role_assignment_request, target_user: other,   requested_by: @requester)
    assert_includes     RoleAssignmentRequest.for_user(@target), req1
    refute_includes     RoleAssignmentRequest.for_user(@target), req2
  end
end
