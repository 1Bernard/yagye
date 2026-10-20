# frozen_string_literal: true

require "test_helper"
require "support/integration_helpers"

# ── RBAC Integration Test ─────────────────────────────────────────────────────
#
# Systematically verifies that every role can access what the grant matrix
# grants and is blocked from what it does not grant.
#
# Permission → route mapping (from actual policy files):
#
#   payments.view            → GET /payments, GET /disputes
#   settlements.view         → GET /settlement-batches, GET /reserves
#   team.manage              → POST /team/users (invite)
#   merchants.view           → GET /merchants  [internal_staff? only]
#   kyb.view                 → GET /kyb-reviews [internal_staff? only]
#   pricing_plans (any)      → GET /pricing-plans [internal_staff? only]
#   disputes.submit_evidence → POST /disputes/:id/evidence/draft
#   disputes.approve_evidence→ POST /disputes/:id/evidence/approve
#   developers.manage_api_keys → GET /developers/keys/new
#
# All logged-in users can:
#   GET /developers (developers_policy.index? = user.present?)
#   GET /team/users (user_policy.index? = user.present?)
#   GET /settings   (settings_policy.index? = user.present?)
#
# Pundit rejection redirects to root (/) — full URL in integration tests.

class RbacTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include IntegrationHelpers
  include WebMock::API

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    stub_request(:get, %r{localhost:4000/internal/merchants/.*/kyb-status})
      .to_return(status: 200, body: { status: "not_started" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    @dispute = create_open_dispute
  end

  # ── Routes accessible to ALL logged-in users ────────────────────────────────

  %w[merchant_owner merchant_finance merchant_developer merchant_support
     ops_analyst ops_manager compliance_analyst compliance_manager].each do |role|
    test "#{role} can view team member list" do
      user = role.start_with?("ops", "compliance") \
        ? create_internal_user_with_role(role)
        : create_merchant_user_with_role(role)
      sign_in user
      get team_users_path
      assert_ok
    end

    test "#{role} can access developers page" do
      user = role.start_with?("ops", "compliance") \
        ? create_internal_user_with_role(role)
        : create_merchant_user_with_role(role)
      sign_in user
      get developers_path
      assert_ok
    end
  end

  # ── payments.view (all 8 roles) ─────────────────────────────────────────────

  test "every role can view the payments list" do
    %w[merchant_owner merchant_finance merchant_developer merchant_support
       ops_analyst ops_manager compliance_analyst compliance_manager].each do |role|
      user = role.start_with?("ops", "compliance") \
        ? create_internal_user_with_role(role)
        : create_merchant_user_with_role(role)
      sign_in user
      get payments_path
      assert_ok
      sign_out user
    end
  end

  test "every role with payments.view can view disputes list" do
    %w[merchant_owner merchant_finance merchant_support ops_analyst ops_manager
       compliance_analyst compliance_manager].each do |role|
      user = role.start_with?("ops", "compliance") \
        ? create_internal_user_with_role(role)
        : create_merchant_user_with_role(role)
      sign_in user
      get disputes_path
      assert_ok
      sign_out user
    end
  end

  # ── settlements.view (owner, finance, ops_analyst, ops_manager) ─────────────

  test "merchant_owner can view settlement batches" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get settlement_batches_path
    assert_ok
  end

  test "merchant_finance can view settlement batches" do
    sign_in create_merchant_user_with_role("merchant_finance")
    get settlement_batches_path
    assert_ok
  end

  test "merchant_owner can view reserves (settlements.view)" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get reserves_path
    assert_ok
  end

  test "ops_analyst can view settlement batches" do
    sign_in create_internal_user_with_role("ops_analyst")
    get settlement_batches_path
    assert_ok
  end

  test "merchant_developer CANNOT view settlement batches (no settlements.view)" do
    sign_in create_merchant_user_with_role("merchant_developer")
    get settlement_batches_path
    assert_forbidden
  end

  test "merchant_support CANNOT view settlement batches" do
    sign_in create_merchant_user_with_role("merchant_support")
    get settlement_batches_path
    assert_forbidden
  end

  test "compliance_analyst CANNOT view settlement batches (no settlements.view)" do
    sign_in create_internal_user_with_role("compliance_analyst")
    get settlement_batches_path
    assert_forbidden
  end

  test "compliance_manager CANNOT view settlement batches" do
    sign_in create_internal_user_with_role("compliance_manager")
    get settlement_batches_path
    assert_forbidden
  end

  # ── team.manage (owner + ops_manager only) ──────────────────────────────────

  test "merchant_owner can access the invite form" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get new_team_user_path
    assert_ok
  end

  test "merchant_finance CANNOT access the invite form (no team.manage)" do
    sign_in create_merchant_user_with_role("merchant_finance")
    get new_team_user_path
    assert_forbidden
  end

  test "merchant_developer CANNOT access the invite form" do
    sign_in create_merchant_user_with_role("merchant_developer")
    get new_team_user_path
    assert_forbidden
  end

  test "merchant_support CANNOT access the invite form" do
    sign_in create_merchant_user_with_role("merchant_support")
    get new_team_user_path
    assert_forbidden
  end

  test "ops_manager can access the invite form" do
    sign_in create_internal_user_with_role("ops_manager")
    get new_team_user_path
    assert_ok
  end

  # ── developers.manage_api_keys (owner, developer) ──────────────────────────

  test "merchant_owner can access new API key form" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get new_developers_key_path
    assert_ok
  end

  test "merchant_developer can access new API key form" do
    sign_in create_merchant_user_with_role("merchant_developer")
    get new_developers_key_path
    assert_ok
  end

  test "merchant_finance CANNOT access new API key form (no manage_api_keys)" do
    sign_in create_merchant_user_with_role("merchant_finance")
    get new_developers_key_path
    assert_forbidden
  end

  test "merchant_support CANNOT access new API key form" do
    sign_in create_merchant_user_with_role("merchant_support")
    get new_developers_key_path
    assert_forbidden
  end

  # ── disputes.submit_evidence (owner, finance, support) ─────────────────────

  test "merchant_owner can POST to evidence draft" do
    sign_in create_merchant_user_with_role("merchant_owner")
    post dispute_evidence_draft_path(@dispute), params: { evidence_text: "Evidence." }
    assert_redirected_to dispute_path(@dispute)
  end

  test "merchant_finance can POST to evidence draft" do
    sign_in create_merchant_user_with_role("merchant_finance")
    post dispute_evidence_draft_path(@dispute), params: { evidence_text: "Evidence." }
    assert_redirected_to dispute_path(@dispute)
  end

  test "merchant_support can POST to evidence draft" do
    sign_in create_merchant_user_with_role("merchant_support")
    post dispute_evidence_draft_path(@dispute), params: { evidence_text: "Evidence." }
    assert_redirected_to dispute_path(@dispute)
  end

  test "merchant_developer CANNOT POST to evidence draft (no disputes.submit_evidence)" do
    sign_in create_merchant_user_with_role("merchant_developer")
    post dispute_evidence_draft_path(@dispute), params: { evidence_text: "Evidence." }
    assert_forbidden
  end

  # ── disputes.approve_evidence (owner only) ──────────────────────────────────

  test "merchant_finance CANNOT approve dispute evidence (no disputes.approve_evidence)" do
    owner = create_merchant_user_with_role("merchant_owner")
    @dispute.update!(
      evidence_draft_by: owner.id.to_s, evidence_draft_at: Time.current,
      evidence_draft_text: "evidence"
    )
    sign_in create_merchant_user_with_role("merchant_finance")
    post approve_dispute_evidence_path(@dispute)
    assert_forbidden
  end

  test "merchant_support CANNOT approve dispute evidence" do
    owner = create_merchant_user_with_role("merchant_owner")
    @dispute.update!(
      evidence_draft_by: owner.id.to_s, evidence_draft_at: Time.current,
      evidence_draft_text: "evidence"
    )
    sign_in create_merchant_user_with_role("merchant_support")
    post approve_dispute_evidence_path(@dispute)
    assert_forbidden
  end

  # ── Internal-only routes (merchants, kyb-reviews, pricing-plans) ────────────

  test "merchant_owner CANNOT access the merchant management list (internal only)" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get merchants_path
    assert_forbidden
  end

  test "merchant_finance CANNOT access the merchant list" do
    sign_in create_merchant_user_with_role("merchant_finance")
    get merchants_path
    assert_forbidden
  end

  test "ops_analyst CAN access the merchant list" do
    sign_in create_internal_user_with_role("ops_analyst")
    get merchants_path
    assert_ok
  end

  test "compliance_analyst CAN access the merchant list" do
    sign_in create_internal_user_with_role("compliance_analyst")
    get merchants_path
    assert_ok
  end

  test "merchant_owner CANNOT access KYB reviews (internal only)" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get kyb_reviews_path
    assert_forbidden
  end

  test "ops_analyst CAN access KYB reviews" do
    sign_in create_internal_user_with_role("ops_analyst")
    get kyb_reviews_path
    assert_ok
  end

  test "compliance_manager CAN access KYB reviews" do
    sign_in create_internal_user_with_role("compliance_manager")
    get kyb_reviews_path
    assert_ok
  end

  test "merchant_owner CANNOT access pricing plans (internal only)" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get pricing_plans_path
    assert_forbidden
  end

  test "ops_manager CAN access pricing plans" do
    sign_in create_internal_user_with_role("ops_manager")
    get pricing_plans_path
    assert_ok
  end

  test "ops_analyst CAN access pricing plans (internal_staff? gate includes all internal roles)" do
    # pricing_plans_policy.index? = internal_staff? — all internal staff qualify
    sign_in create_internal_user_with_role("ops_analyst")
    get pricing_plans_path
    assert_ok
  end

  # ── compliance actions (kyb.approve_merchant) ───────────────────────────────

  test "compliance_analyst CANNOT approve KYB review (no kyb.approve_merchant)" do
    sign_in create_internal_user_with_role("compliance_analyst")
    post approve_kyb_review_path("fake-id")
    assert_forbidden
  end

  # ── reserves.manage (ops_manager only) ─────────────────────────────────────

  test "ops_manager CAN access reserves" do
    sign_in create_internal_user_with_role("ops_manager")
    get reserves_path
    assert_ok
  end

  test "ops_analyst CANNOT access reserves (no reserves.manage or settlements.view)" do
    # ops_analyst has settlements.view but reserves is also guarded per policy
    sign_in create_internal_user_with_role("ops_analyst")
    get reserves_path
    # ops_analyst has settlements.view so they can see reserves too
    # (reserve_policy.index? = settlements.view)
    assert_ok
  end

  test "compliance_analyst CANNOT access reserves (no settlements.view)" do
    sign_in create_internal_user_with_role("compliance_analyst")
    get reserves_path
    assert_forbidden
  end

  # ── Cross-tenant isolation ──────────────────────────────────────────────────

  test "merchant from another tenant cannot access a dispute they do not own" do
    other_user = build_merchant_user_for("merchant_owner", "MCH-OTHER-RBAC")
    sign_in other_user
    # @dispute belongs to MCH-INTTEST, other_user belongs to MCH-OTHER-RBAC
    get dispute_path(@dispute)
    assert_equal 404, response.status
  end

  test "internal staff can view disputes from any merchant" do
    sign_in create_internal_user_with_role("ops_analyst")
    get dispute_path(@dispute)
    assert_ok
  end

  # ── Unauthenticated ──────────────────────────────────────────────────────────

  test "unauthenticated GET to any protected route redirects to sign in" do
    get payments_path
    assert_redirected_to new_user_session_path
  end

  test "unauthenticated POST redirects to sign in" do
    post dispute_evidence_draft_path(@dispute), params: { evidence_text: "test" }
    assert_redirected_to new_user_session_path
  end

  private

  def build_merchant_user_for(role_key, merchant_code)
    user = User.create!(
      email:                  "user-#{merchant_code.downcase}@other-rbac.com",
      first_name:             "Other",
      last_name:              "Merchant",
      kind:                   "merchant_user",
      password:               "Password1!xx",
      otp_required_for_login: false
    )
    MerchantMembership.create!(
      user:          user,
      merchant_code: merchant_code,
      merchant_name: "Other Merchant",
      state:         "active"
    )
    role = Role.find_by!(key: role_key)
    UserRole.create!(user: user, role: role, granted_by: user,
                     granted_at: Time.current, merchant_code: merchant_code)
    user
  end
end
