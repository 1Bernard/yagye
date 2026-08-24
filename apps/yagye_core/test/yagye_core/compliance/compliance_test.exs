defmodule YagyeCore.Compliance.ComplianceTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Compliance
  alias YagyeCore.Fixtures
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Repo

  # ──────────────────────────────────────────────────────────────────────────
  # submit_onboarding/2
  # ──────────────────────────────────────────────────────────────────────────
  describe "submit_onboarding/2" do
    test "updates onboarding_state and returns the merchant" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, updated} =
               Compliance.submit_onboarding(merchant.public_id, %{
                 business_type: "ecommerce",
                 website_url: "https://acmepay.com",
                 expected_monthly_volume_minor: 5_000_000,
                 expected_monthly_volume_currency: "GBP"
               })

      assert updated.id == merchant.id
      assert updated.onboarding_state == "basic_info_submitted"
    end

    test "emits compliance.onboarding_submitted outbox event" do
      merchant = Fixtures.merchant_fixture()
      {:ok, updated} = Compliance.submit_onboarding(merchant.public_id, %{business_type: "saas"})

      msg =
        Repo.get_by(OutboxMessage,
          aggregate_type: "merchant",
          aggregate_id: updated.id,
          event_type: "compliance.onboarding_submitted"
        )

      assert msg != nil
    end

    test "accepts minimal attrs (only business_type)" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, _updated} =
               Compliance.submit_onboarding(merchant.public_id, %{business_type: "saas"})
    end

    test "returns not_found for unknown merchant_id" do
      assert {:error, :not_found} =
               Compliance.submit_onboarding("mch_nonexistent", %{business_type: "retail"})
    end

    test "returns invalid_onboarding_state when merchant is not in a submittable state" do
      merchant = Fixtures.merchant_fixture()

      import Ecto.Query

      Repo.update_all(
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

    test "creates a beneficial owner and returns it", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      assert {:ok, owner} =
               Compliance.add_beneficial_owner(merchant.public_id, %{
                 subject_ref: subject_ref,
                 role: "ubo",
                 ownership_bps: 5000
               })

      assert owner.merchant_id == merchant.id
      assert owner.role == "ubo"
      assert owner.ownership_bps == 5000
    end

    test "emits compliance.beneficial_owner_added outbox event", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, owner} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref,
          role: "ubo"
        })

      msg =
        Repo.get_by(OutboxMessage,
          aggregate_type: "beneficialowner",
          aggregate_id: owner.id,
          event_type: "compliance.beneficial_owner_added"
        )

      assert msg != nil
    end

    test "accepts all valid roles", %{merchant: merchant} do
      for role <- ["director", "ubo", "both"] do
        subject_ref = Fixtures.pii_vault_fixture()

        assert {:ok, owner} =
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

    test "creates a KYB document record and returns it", %{merchant: merchant} do
      assert {:ok, doc} =
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

    test "emits compliance.kyb_document_uploaded outbox event", %{merchant: merchant} do
      {:ok, doc} =
        Compliance.upload_document(merchant.public_id, %{
          kind: "incorporation",
          s3_key: "kyb/doc.pdf",
          checksum: "csum",
          uploaded_by: "user:usr_test"
        })

      msg =
        Repo.get_by(OutboxMessage,
          aggregate_type: "kybdocument",
          aggregate_id: doc.id,
          event_type: "compliance.kyb_document_uploaded"
        )

      assert msg != nil
    end

    test "accepts all valid document kinds", %{merchant: merchant} do
      for kind <- ["incorporation", "id", "proof_of_address", "bank_confirmation"] do
        assert {:ok, doc} =
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
