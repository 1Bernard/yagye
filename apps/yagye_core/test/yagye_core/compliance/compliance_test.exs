defmodule YagyeCore.Compliance.ComplianceTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Compliance
  alias YagyeCore.Fixtures

  # ──────────────────────────────────────────────────────────────────────────
  # submit_onboarding/2
  # ──────────────────────────────────────────────────────────────────────────
  describe "submit_onboarding/2" do
    test "updates onboarding_state and returns merchant + event" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, {updated, event}} =
               Compliance.submit_onboarding(merchant.public_id, %{
                 business_type: "ecommerce",
                 website_url: "https://acmepay.com",
                 expected_monthly_volume_minor: 5_000_000,
                 expected_monthly_volume_currency: "GBP"
               })

      assert updated.id == merchant.id
      assert updated.onboarding_state == "details_submitted"
      assert event.merchant_id == merchant.id
    end

    test "accepts minimal attrs (only business_type)" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, {_updated, _event}} =
               Compliance.submit_onboarding(merchant.public_id, %{business_type: "saas"})
    end

    test "returns not_found for unknown merchant_id" do
      assert {:error, :not_found} =
               Compliance.submit_onboarding("mch_nonexistent", %{business_type: "retail"})
    end

    test "returns invalid_onboarding_state when merchant is not in a submittable state" do
      merchant = Fixtures.merchant_fixture()

      import Ecto.Query

      YagyeCore.Repo.update_all(
        from(m in YagyeCore.Merchants.Schemas.Merchant, where: m.id == ^merchant.id),
        set: [onboarding_state: "under_review"]
      )

      assert {:error, :invalid_onboarding_state} =
               Compliance.submit_onboarding(merchant.public_id, %{business_type: "retail"})
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # add_beneficial_owner/2
  # ──────────────────────────────────────────────────────────────────────────
  describe "add_beneficial_owner/2" do
    setup do
      %{merchant: Fixtures.merchant_fixture()}
    end

    test "creates a beneficial owner and returns {owner, event}", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      assert {:ok, {owner, _event}} =
               Compliance.add_beneficial_owner(merchant.public_id, %{
                 subject_ref: subject_ref,
                 role: "ubo",
                 ownership_bps: 5000
               })

      assert owner.merchant_id == merchant.id
      assert owner.role == "ubo"
      assert owner.ownership_bps == 5000
    end

    test "accepts all valid roles", %{merchant: merchant} do
      for role <- ["director", "ubo", "both"] do
        subject_ref = Fixtures.pii_vault_fixture()

        assert {:ok, {owner, _event}} =
                 Compliance.add_beneficial_owner(merchant.public_id, %{
                   subject_ref: subject_ref,
                   role: role
                 })

        assert owner.role == role
      end
    end

    test "returns changeset error for invalid role", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      assert {:error, changeset} =
               Compliance.add_beneficial_owner(merchant.public_id, %{
                 subject_ref: subject_ref,
                 role: "janitor"
               })

      assert %{role: _} = errors_on(changeset)
    end

    test "returns not_found for unknown merchant_id" do
      assert {:error, :not_found} =
               Compliance.add_beneficial_owner("mch_nonexistent", %{
                 subject_ref: Uniq.UUID.uuid7(),
                 role: "ubo"
               })
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # upload_document/2
  # ──────────────────────────────────────────────────────────────────────────
  describe "upload_document/2" do
    setup do
      %{merchant: Fixtures.merchant_fixture()}
    end

    test "creates a KYB document record and returns {doc, event}", %{merchant: merchant} do
      assert {:ok, {doc, _event}} =
               Compliance.upload_document(merchant.public_id, %{
                 kind: "incorporation",
                 s3_key: "kyb/mch_abc/cert.pdf",
                 checksum: "abc123def456",
                 uploaded_by: "user:usr_test"
               })

      assert doc.merchant_id == merchant.id
      assert doc.kind == "incorporation"
      assert doc.s3_key == "kyb/mch_abc/cert.pdf"
      assert doc.checksum == "abc123def456"
    end

    test "accepts all valid document kinds", %{merchant: merchant} do
      for kind <- ["incorporation", "id", "proof_of_address", "bank_confirmation"] do
        assert {:ok, {doc, _event}} =
                 Compliance.upload_document(merchant.public_id, %{
                   kind: kind,
                   s3_key: "kyb/doc.pdf",
                   checksum: "csum_#{kind}",
                   uploaded_by: "user:usr_test"
                 })

        assert doc.kind == kind
      end
    end

    test "returns changeset error for invalid kind", %{merchant: merchant} do
      assert {:error, changeset} =
               Compliance.upload_document(merchant.public_id, %{
                 kind: "selfie",
                 s3_key: "kyb/doc.pdf",
                 checksum: "csum",
                 uploaded_by: "user:usr_test"
               })

      assert %{kind: _} = errors_on(changeset)
    end

    test "returns not_found for unknown merchant_id" do
      assert {:error, :not_found} =
               Compliance.upload_document("mch_nonexistent", %{
                 kind: "id",
                 s3_key: "kyb/doc.pdf",
                 checksum: "csum",
                 uploaded_by: "user:usr_test"
               })
    end
  end
end
