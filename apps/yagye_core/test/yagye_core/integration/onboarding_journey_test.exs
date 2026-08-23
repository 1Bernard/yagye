defmodule YagyeCore.Integration.OnboardingJourneyTest do
  @moduledoc """
  Phase gate test for P1: Merchants, Onboarding & Access.

  Walks a merchant through the full KYB onboarding sequence in order and
  asserts the final state is `details_submitted` — the prerequisite for a
  compliance reviewer to move the merchant to `under_review`.

  If this test is green, Phase 1 is structurally complete.
  """

  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Compliance, Fixtures, Merchants}

  test "full onboarding journey: register → issue key → submit details → add owner → upload doc → details_submitted" do
    # Step 1 — merchant is created in simulation mode
    assert {:ok, {merchant, _}} =
             Merchants.create_merchant(%{
               legal_name: "Acme Payments Ltd",
               trading_name: "Acme Pay",
               country: "GB",
               default_currency: "GBP"
             })

    assert merchant.status == "registered"
    assert merchant.onboarding_state == "registered"
    assert Merchants.live_mode_enabled?(merchant.id) == false

    # Step 2 — a KYB-scoped API key is issued
    assert {:ok, {api_key, _raw, _event}} =
             Merchants.issue_api_key(merchant.public_id, %{
               kind: "secret",
               mode: "simulation",
               scopes: ["kyb:write"]
             })

    assert api_key.merchant_id == merchant.id
    assert "kyb:write" in api_key.scopes

    # Step 3 — onboarding details are submitted
    assert {:ok, {after_submit, _}} =
             Compliance.submit_onboarding(merchant.public_id, %{
               business_type: "ecommerce",
               website_url: "https://acmepay.com",
               expected_monthly_volume_minor: 5_000_000,
               expected_monthly_volume_currency: "GBP"
             })

    assert after_submit.onboarding_state == "details_submitted"
    assert get_in(after_submit.metadata, [:onboarding, :business_type]) == "ecommerce"

    # Re-submission is idempotent (already in details_submitted, still allowed)
    assert {:ok, {resubmit, _}} =
             Compliance.submit_onboarding(merchant.public_id, %{business_type: "saas"})

    assert resubmit.onboarding_state == "details_submitted"

    # Step 4 — a beneficial owner is added
    subject_ref = Fixtures.pii_vault_fixture()

    assert {:ok, {owner, _}} =
             Compliance.add_beneficial_owner(merchant.public_id, %{
               subject_ref: subject_ref,
               role: "ubo",
               ownership_bps: 10_000
             })

    assert owner.merchant_id == merchant.id
    assert owner.ownership_bps == 10_000

    # Step 5 — a KYB document is uploaded
    assert {:ok, {doc, _}} =
             Compliance.upload_document(merchant.public_id, %{
               kind: "incorporation",
               s3_key: "kyb/#{merchant.public_id}/cert_of_incorporation.pdf",
               checksum: "sha256:abc123",
               uploaded_by: "user:usr_compliance_agent"
             })

    assert doc.merchant_id == merchant.id
    assert doc.kind == "incorporation"

    # Phase gate — merchant is now in details_submitted; a reviewer can move to under_review
    {:ok, final} = Merchants.get_merchant(merchant.public_id)
    assert final.onboarding_state == "details_submitted"
    assert final.status == "registered"

    # Live mode is still locked — only enabled after merchant.approve/2
    assert Merchants.live_mode_enabled?(merchant.id) == false
  end
end
