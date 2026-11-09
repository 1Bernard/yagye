# frozen_string_literal: true

require "test_helper"
require "support/integration_helpers"

# Integration tests for Risk::FlaggedPaymentsController.
#
# Access rules:
#   - Only internal_staff may access any risk route
#   - Within internal_staff, risk.view permission is required (ops_analyst, ops_manager,
#     compliance_analyst, compliance_manager all have it)
#   - risk.disposition is required for the dispose action (ops_manager, compliance_manager)
#   - Merchants are always redirected to root
class RiskFlaggedPaymentsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include IntegrationHelpers
  include WebMock::API

  CORE_URL = ENV.fetch("CORE_API_URL", "http://localhost:4000")

  FLAGGED_LIST_RESPONSE = {
    "data"     => [
      {
        "id"             => "pay-uuid-1",
        "public_id"      => "pay_test_abc",
        "merchant_id"    => 1,
        "amount"         => 10_000,
        "currency"       => "GHS",
        "state"          => "succeeded",
        "method"         => "mobile_money",
        "risk_score"     => 0.9123,
        "risk_decision"  => "review",
        "risk_flagged_at" => "2026-11-01T10:00:00Z",
        "inserted_at"    => "2026-11-01T09:55:00Z"
      }
    ],
    "has_more"  => false,
    "next"      => nil
  }.freeze

  FLAGGED_SHOW_RESPONSE = {
    "payment" => {
      "id"             => "pay-uuid-1",
      "public_id"      => "pay_test_abc",
      "merchant_id"    => 1,
      "amount"         => 10_000,
      "currency"       => "GHS",
      "state"          => "succeeded",
      "method"         => "mobile_money",
      "risk_score"     => 0.9123,
      "risk_decision"  => "review",
      "risk_flagged_at" => "2026-11-01T10:00:00Z"
    },
    "labels"  => []
  }.freeze

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    stub_core_flagged_list
    stub_core_flagged_show
    stub_core_dispose_success
  end

  # ── Access control ──────────────────────────────────────────────────────────

  test "merchant user is redirected to root" do
    sign_in create_merchant_user_with_role("merchant_owner")
    get risk_flagged_payments_path
    assert_redirected_to root_path
  end

  test "ops_analyst with risk.view can access index" do
    sign_in create_internal_user_with_role("ops_analyst")
    get risk_flagged_payments_path
    assert_ok
  end

  test "compliance_analyst with risk.view can access index" do
    sign_in create_internal_user_with_role("compliance_analyst")
    get risk_flagged_payments_path
    assert_ok
  end

  test "ops_analyst can view a flagged payment case" do
    sign_in create_internal_user_with_role("ops_analyst")
    get risk_flagged_payment_path("pay-uuid-1")
    assert_ok
  end

  # ── Disposition SoD ─────────────────────────────────────────────────────────

  test "ops_analyst without risk.disposition cannot dispose" do
    sign_in create_internal_user_with_role("ops_analyst")
    post dispose_risk_flagged_payment_path("pay-uuid-1"),
         params: { label: "false_positive", note: "benign" }
    # ops_analyst does not have risk.disposition — expect Pundit redirect
    assert_includes [302, 403], response.status
  end

  test "ops_manager with risk.disposition can dispose a case" do
    sign_in create_internal_user_with_role("ops_manager")
    post dispose_risk_flagged_payment_path("pay-uuid-1"),
         params: { label: "false_positive", note: "benign" }
    assert_redirected_to risk_flagged_payment_path("pay-uuid-1")
    assert_equal "Case dispositioned.", flash[:notice]
  end

  test "compliance_manager with risk.disposition can dispose a case" do
    sign_in create_internal_user_with_role("compliance_manager")
    post dispose_risk_flagged_payment_path("pay-uuid-1"),
         params: { label: "confirmed_fraud", note: "confirmed" }
    assert_redirected_to risk_flagged_payment_path("pay-uuid-1")
    assert_equal "Case dispositioned.", flash[:notice]
  end

  # ── SAR export ──────────────────────────────────────────────────────────────

  test "ops_analyst can download SAR PDF" do
    sign_in create_internal_user_with_role("ops_analyst")
    get sar_risk_flagged_payment_path("pay-uuid-1")
    assert_equal 200, response.status
    assert_equal "application/pdf", response.content_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/SAR-pay_test_abc/, response.headers["Content-Disposition"])
  end

  test "SAR download returns 302 when payment not found" do
    stub_request(:get, "#{CORE_URL}/internal/risk/flagged-payments/nonexistent")
      .to_return(status: 404, body: { error: "not_found" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    sign_in create_internal_user_with_role("ops_analyst")
    get sar_risk_flagged_payment_path("nonexistent")
    assert_redirected_to risk_flagged_payments_path
  end

  private

  def stub_core_flagged_list
    stub_request(:get, %r{#{CORE_URL}/internal/risk/flagged-payments})
      .with(query: hash_including("decision" => anything))
      .to_return(
        status:  200,
        body:    FLAGGED_LIST_RESPONSE.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_core_flagged_show
    stub_request(:get, "#{CORE_URL}/internal/risk/flagged-payments/pay-uuid-1")
      .to_return(
        status:  200,
        body:    FLAGGED_SHOW_RESPONSE.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_core_dispose_success
    stub_request(:post, "#{CORE_URL}/internal/risk/flagged-payments/pay-uuid-1/dispose")
      .to_return(
        status:  200,
        body:    { ok: true }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
