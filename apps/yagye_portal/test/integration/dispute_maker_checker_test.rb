# frozen_string_literal: true

require "test_helper"
require "support/integration_helpers"

# ── Dispute Maker-Checker (Two-Person Integrity) Test ─────────────────────────
#
# Verifies the PSP industry-standard requirement that the person who drafts
# dispute evidence cannot be the same person who approves and submits it.
#
# Grant matrix:
#   disputes.submit_evidence  → owner, finance, support
#   disputes.approve_evidence → owner only
#
# Valid flows:
#   finance drafts → owner approves    ✓
#   support drafts → owner approves    ✓
#   owner1 drafts  → owner2 approves   ✓ (two different owners on same merchant)
#
# Blocked flows:
#   owner drafts   → owner approves    ✗  (same person; SoD violation)
#   finance drafts → finance approves  ✗  (no approve_evidence permission)
#   After evidence submitted → new draft blocked

class DisputeMakerCheckerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include IntegrationHelpers
  include WebMock::API

  CORE_API_URL = "http://localhost:4000"

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    # KYB banner is fetched on every merchant page — stub globally.
    stub_request(:get, %r{localhost:4000/internal/merchants/.*/kyb-status})
      .to_return(status: 200, body: { status: "not_started" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    @dispute = create_open_dispute
    @owner   = create_merchant_user_with_role("merchant_owner")
    @finance = create_merchant_user_with_role("merchant_finance")
    @support = create_merchant_user_with_role("merchant_support")
  end

  # ── Drafting ────────────────────────────────────────────────────────────────

  test "merchant_owner can save an evidence draft" do
    sign_in @owner
    post dispute_evidence_draft_path(@dispute),
         params: { evidence_text: "Customer confirmed transaction." }

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :draft,          @dispute.evidence_stage
    assert_equal "Customer confirmed transaction.", @dispute.evidence_draft_text
    assert_equal @owner.id.to_s,  @dispute.evidence_draft_by
    assert_not_nil                @dispute.evidence_draft_at
  end

  test "merchant_finance can save an evidence draft" do
    sign_in @finance
    post dispute_evidence_draft_path(@dispute),
         params: { evidence_text: "Bank statement attached." }

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :draft,           @dispute.evidence_stage
    assert_equal @finance.id.to_s, @dispute.evidence_draft_by
  end

  test "merchant_support can save an evidence draft" do
    sign_in @support
    post dispute_evidence_draft_path(@dispute),
         params: { evidence_text: "Support notes attached." }

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :draft,           @dispute.evidence_stage
    assert_equal @support.id.to_s, @dispute.evidence_draft_by
  end

  test "cannot draft if evidence is already submitted" do
    @dispute.update!(
      evidence_submitted_at: Time.current,
      evidence_text: "already submitted"
    )
    sign_in @owner
    post dispute_evidence_draft_path(@dispute),
         params: { evidence_text: "new draft attempt" }

    # Redirected away with an alert — draft is blocked once submitted
    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    # evidence_draft fields are NOT updated
    assert_nil @dispute.evidence_draft_by
  end

  test "cannot draft on a closed dispute" do
    @dispute.update!(status: "won", resolved_at: Time.current)
    sign_in @owner
    post dispute_evidence_draft_path(@dispute),
         params: { evidence_text: "Late evidence" }

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_nil @dispute.evidence_draft_by
  end

  test "evidence draft requires text or files" do
    sign_in @owner
    post dispute_evidence_draft_path(@dispute), params: { evidence_text: "" }

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_nil @dispute.evidence_draft_by
  end

  # ── Approval (SoD enforcement) ──────────────────────────────────────────────

  test "owner2 can approve a draft created by owner1 (different person, same role)" do
    # owner1 creates the draft
    @dispute.update!(
      evidence_draft_text: "Evidence text from owner1",
      evidence_draft_by:   @owner.id.to_s,
      evidence_draft_at:   Time.current
    )

    # stub Core API
    stub_request(:post, "#{CORE_API_URL}/internal/disputes/#{@dispute.core_dispute_id}/evidence")
      .to_return(status: 200, body: { status: "evidence_submitted" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    owner2 = create_merchant_user_with_role("merchant_owner")
    sign_in owner2

    post approve_dispute_evidence_path(@dispute)

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :submitted,       @dispute.evidence_stage
    assert_not_nil                 @dispute.evidence_submitted_at
    assert_equal owner2.id.to_s,   @dispute.evidence_approved_by
  end

  test "finance draft → owner approves (the canonical maker-checker flow)" do
    # Finance is the maker
    @dispute.update!(
      evidence_draft_text: "Statement from finance team",
      evidence_draft_by:   @finance.id.to_s,
      evidence_draft_at:   Time.current
    )

    stub_request(:post, "#{CORE_API_URL}/internal/disputes/#{@dispute.core_dispute_id}/evidence")
      .to_return(status: 200, body: { status: "evidence_submitted" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    sign_in @owner
    post approve_dispute_evidence_path(@dispute)

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :submitted,      @dispute.evidence_stage
    assert_equal @owner.id.to_s,  @dispute.evidence_approved_by
  end

  test "support draft → owner approves" do
    @dispute.update!(
      evidence_draft_text: "Support agent notes",
      evidence_draft_by:   @support.id.to_s,
      evidence_draft_at:   Time.current
    )

    stub_request(:post, "#{CORE_API_URL}/internal/disputes/#{@dispute.core_dispute_id}/evidence")
      .to_return(status: 200, body: { status: "evidence_submitted" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    sign_in @owner
    post approve_dispute_evidence_path(@dispute)

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :submitted, @dispute.evidence_stage
  end

  # ── SoD violation: drafter cannot approve their own draft ──────────────────

  test "owner CANNOT approve evidence they drafted (same person)" do
    @dispute.update!(
      evidence_draft_text: "My own draft",
      evidence_draft_by:   @owner.id.to_s,
      evidence_draft_at:   Time.current
    )

    sign_in @owner
    post approve_dispute_evidence_path(@dispute)

    # Redirected back with alert — SoD blocked
    assert_redirected_to dispute_path(@dispute)
    follow_redirect!
    assert_match(/cannot approve evidence you prepared/i, response.body)

    @dispute.reload
    assert_equal :draft, @dispute.evidence_stage  # still draft, not submitted
  end

  # ── No approve_evidence permission ─────────────────────────────────────────

  test "merchant_finance CANNOT approve evidence (no disputes.approve_evidence)" do
    @dispute.update!(
      evidence_draft_text: "evidence",
      evidence_draft_by:   @owner.id.to_s,
      evidence_draft_at:   Time.current
    )

    sign_in @finance
    post approve_dispute_evidence_path(@dispute)
    assert_forbidden

    @dispute.reload
    assert_equal :draft, @dispute.evidence_stage
  end

  test "merchant_support CANNOT approve evidence (no disputes.approve_evidence)" do
    @dispute.update!(
      evidence_draft_text: "evidence",
      evidence_draft_by:   @owner.id.to_s,
      evidence_draft_at:   Time.current
    )

    sign_in @support
    post approve_dispute_evidence_path(@dispute)
    assert_forbidden
  end

  # ── Discard draft ──────────────────────────────────────────────────────────

  test "drafter can discard their own draft" do
    @dispute.update!(
      evidence_draft_text: "Draft to discard",
      evidence_draft_by:   @finance.id.to_s,
      evidence_draft_at:   Time.current
    )

    sign_in @finance
    delete discard_dispute_evidence_draft_path(@dispute)

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :none, @dispute.evidence_stage
    assert_nil @dispute.evidence_draft_by
    assert_nil @dispute.evidence_draft_at
    assert_nil @dispute.evidence_draft_text
  end

  test "owner can discard a draft created by finance (either party can discard)" do
    @dispute.update!(
      evidence_draft_text: "Finance draft",
      evidence_draft_by:   @finance.id.to_s,
      evidence_draft_at:   Time.current
    )

    sign_in @owner
    delete discard_dispute_evidence_draft_path(@dispute)

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :none, @dispute.evidence_stage
  end

  test "cannot discard when no draft exists" do
    sign_in @owner
    delete discard_dispute_evidence_draft_path(@dispute)

    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :none, @dispute.evidence_stage  # nothing changed
  end

  # ── Core API failure on approval ───────────────────────────────────────────

  test "dispute remains in draft if Core API returns an error on approval" do
    @dispute.update!(
      evidence_draft_text: "Evidence",
      evidence_draft_by:   @finance.id.to_s,
      evidence_draft_at:   Time.current
    )

    # Core API returns 422
    stub_request(:post, "#{CORE_API_URL}/internal/disputes/#{@dispute.core_dispute_id}/evidence")
      .to_return(status: 422,
                 body: { error: { code: "invalid_state", message: "Dispute not open" } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    sign_in @owner
    post approve_dispute_evidence_path(@dispute)

    # Still redirected to dispute but evidence not promoted
    assert_redirected_to dispute_path(@dispute)
    @dispute.reload
    assert_equal :draft, @dispute.evidence_stage
    assert_nil @dispute.evidence_submitted_at
  end
end
