defmodule YagyeCore.Compliance.ComplianceTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Compliance
  alias YagyeCore.Compliance.Schemas.ScreeningSubject
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

    test "enrols a screening subject on creation", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, owner} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref,
          role: "ubo",
          ownership_bps: 5000
        })

      screening_subject =
        Repo.get_by(ScreeningSubject,
          subject_type: "beneficial_owner",
          subject_id: owner.id
        )

      assert screening_subject != nil
      assert screening_subject.screening_status == "pending"
      assert screening_subject.merchant_id == owner.merchant_id
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
  # list_beneficial_owners/1
  # ──────────────────────────────────────────────────────────────────────────
  describe "list_beneficial_owners/1" do
    setup do
      %{merchant: Fixtures.merchant_fixture()}
    end

    test "returns empty list when no owners", %{merchant: merchant} do
      assert {:ok, []} = Compliance.list_beneficial_owners(merchant.public_id)
    end

    test "returns all owners for the merchant", %{merchant: merchant} do
      subject_ref1 = Fixtures.pii_vault_fixture()
      subject_ref2 = Fixtures.pii_vault_fixture()

      {:ok, _} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref1,
          role: "ubo",
          ownership_bps: 5000
        })

      {:ok, _} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref2,
          role: "director"
        })

      assert {:ok, owners} = Compliance.list_beneficial_owners(merchant.public_id)
      assert length(owners) == 2
    end

    test "does not return owners from another merchant", %{merchant: merchant} do
      other = Fixtures.merchant_fixture()
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, _} =
        Compliance.add_beneficial_owner(other.public_id, %{subject_ref: subject_ref, role: "ubo"})

      assert {:ok, []} = Compliance.list_beneficial_owners(merchant.public_id)
    end

    test "returns not_found for unknown merchant" do
      assert {:error, :not_found} = Compliance.list_beneficial_owners("mch_unknown")
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

    test "generates a placeholder s3_key when none is provided", %{merchant: merchant} do
      assert {:ok, doc} =
               Compliance.upload_document(merchant.public_id, %{
                 kind: "id",
                 checksum: "sha256abc",
                 uploaded_by: "user:usr_test"
               })

      assert doc.kind == "id"
      assert String.starts_with?(doc.s3_key, "kyb/pending/")
    end

    test "emits compliance.kyb_document_uploaded outbox event", %{merchant: merchant} do
      {:ok, doc} =
        Compliance.upload_document(merchant.public_id, %{
          kind: "incorporation",
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
                 checksum: "csum",
                 uploaded_by: "user:usr_test"
               })

      assert %{kind: _} = errors_on(changeset)
    end

    test "returns not_found for unknown merchant_id" do
      assert {:error, :not_found} =
               Compliance.upload_document("mch_nonexistent", %{
                 kind: "id",
                 checksum: "csum",
                 uploaded_by: "user:usr_test"
               })
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # list_documents/1
  # ──────────────────────────────────────────────────────────────────────────
  describe "list_documents/1" do
    setup do
      %{merchant: Fixtures.merchant_fixture()}
    end

    test "returns empty list when no documents", %{merchant: merchant} do
      assert {:ok, []} = Compliance.list_documents(merchant.public_id)
    end

    test "returns all documents for the merchant", %{merchant: merchant} do
      {:ok, _} =
        Compliance.upload_document(merchant.public_id, %{
          kind: "incorporation",
          checksum: "c1",
          uploaded_by: "u"
        })

      {:ok, _} =
        Compliance.upload_document(merchant.public_id, %{
          kind: "id",
          checksum: "c2",
          uploaded_by: "u"
        })

      assert {:ok, docs} = Compliance.list_documents(merchant.public_id)
      assert length(docs) == 2
    end

    test "returns not_found for unknown merchant" do
      assert {:error, :not_found} = Compliance.list_documents("mch_unknown")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # screening_status/1
  # ──────────────────────────────────────────────────────────────────────────
  describe "screening_status/1" do
    setup do
      %{merchant: Fixtures.merchant_fixture()}
    end

    test "returns empty subjects and hits when no owners", %{merchant: merchant} do
      assert {:ok, %{subjects: [], open_hits: []}} =
               Compliance.screening_status(merchant.public_id)
    end

    test "includes screening subject after adding a beneficial owner", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, _} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref,
          role: "ubo",
          ownership_bps: 5000
        })

      assert {:ok, %{subjects: subjects, open_hits: []}} =
               Compliance.screening_status(merchant.public_id)

      assert length(subjects) == 1
      assert hd(subjects).screening_status == "pending"
    end

    test "returns not_found for unknown merchant" do
      assert {:error, :not_found} = Compliance.screening_status("mch_unknown")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # ubo_threshold_cleared?/1
  # ──────────────────────────────────────────────────────────────────────────
  describe "ubo_threshold_cleared?/1" do
    setup do
      %{merchant: Fixtures.merchant_fixture()}
    end

    test "returns true when no qualifying UBOs exist", %{merchant: merchant} do
      assert Compliance.ubo_threshold_cleared?(merchant.id)
    end

    test "returns false when a qualifying UBO has pending screening", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, _} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref,
          role: "ubo",
          ownership_bps: 2500
        })

      # Subject is pending after creation — threshold should not be cleared
      refute Compliance.ubo_threshold_cleared?(merchant.id)
    end

    test "returns true when qualifying UBO has clean screening", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, owner} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref,
          role: "ubo",
          ownership_bps: 2500
        })

      # Manually mark the subject clean (simulating completed ScreeningWorker)
      Repo.update_all(
        from(s in ScreeningSubject, where: s.subject_id == ^owner.id),
        set: [screening_status: "clean"]
      )

      assert Compliance.ubo_threshold_cleared?(merchant.id)
    end

    test "ignores directors with no ownership_bps", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, _} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref,
          role: "director"
        })

      # Director has nil ownership_bps — does not qualify for the 25% check
      assert Compliance.ubo_threshold_cleared?(merchant.id)
    end

    test "ignores UBOs below 25% threshold", %{merchant: merchant} do
      subject_ref = Fixtures.pii_vault_fixture()

      {:ok, _} =
        Compliance.add_beneficial_owner(merchant.public_id, %{
          subject_ref: subject_ref,
          role: "ubo",
          ownership_bps: 2499
        })

      assert Compliance.ubo_threshold_cleared?(merchant.id)
    end
  end
end
