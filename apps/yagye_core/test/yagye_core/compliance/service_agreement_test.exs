defmodule YagyeCore.Compliance.ServiceAgreementTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Compliance
  alias YagyeCore.Compliance.Schemas.{KybDocument, ServiceAgreement}
  alias YagyeCore.Fixtures
  alias YagyeCore.Repo

  # ──────────────────────────────────────────────────────────────────────────
  # accept_service_agreement/2
  # ──────────────────────────────────────────────────────────────────────────
  describe "accept_service_agreement/2" do
    test "records MSA acceptance with signatory evidence" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, agreement} =
               Compliance.accept_service_agreement(merchant.public_id, %{
                 agreement_version: "v2.1",
                 signatory_name: "Kwame Asante",
                 signatory_email: "kwame@example.com",
                 signatory_phone: "+233201234567",
                 signatory_job_title: "CEO",
                 ip_address: "41.66.129.10",
                 user_agent: "Mozilla/5.0"
               })

      assert agreement.agreement_version == "v2.1"
      assert agreement.signatory_name == "Kwame Asante"
      assert agreement.signatory_email == "kwame@example.com"
      assert agreement.ip_address == "41.66.129.10"
      assert agreement.merchant_id == merchant.id
      assert %DateTime{} = agreement.accepted_at
    end

    test "auto-populates accepted_at when not provided" do
      merchant = Fixtures.merchant_fixture()
      before = DateTime.utc_now()

      {:ok, agreement} =
        Compliance.accept_service_agreement(merchant.public_id, %{
          agreement_version: "v2.1",
          signatory_name: "Test User",
          signatory_email: "test@example.com"
        })

      assert DateTime.compare(agreement.accepted_at, before) in [:gt, :eq]
    end

    test "allows multiple agreements (audit trail)" do
      merchant = Fixtures.merchant_fixture()
      attrs = %{agreement_version: "v2.1", signatory_name: "A", signatory_email: "a@b.com"}

      {:ok, _} = Compliance.accept_service_agreement(merchant.public_id, attrs)

      assert {:ok, _} =
               Compliance.accept_service_agreement(
                 merchant.public_id,
                 Map.put(attrs, :agreement_version, "v2.2")
               )

      assert Repo.aggregate(ServiceAgreement, :count, :id) == 2
    end

    test "returns not_found for unknown merchant" do
      assert {:error, :not_found} =
               Compliance.accept_service_agreement("mch_unknown", %{
                 agreement_version: "v2.1",
                 signatory_name: "X",
                 signatory_email: "x@x.com"
               })
    end

    test "requires signatory_email and signatory_name" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               Compliance.accept_service_agreement(merchant.public_id, %{
                 agreement_version: "v2.1"
               })

      assert :signatory_name in Map.keys(errors_on(cs))
      assert :signatory_email in Map.keys(errors_on(cs))
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # review_kyb_document/3
  # ──────────────────────────────────────────────────────────────────────────
  describe "review_kyb_document/3" do
    setup do
      merchant = Fixtures.merchant_fixture()

      {:ok, doc} =
        Compliance.upload_document(merchant.public_id, %{
          kind: "incorporation",
          s3_key: "kyb/test/doc.pdf",
          checksum: "abc123",
          uploaded_by: "user:owner"
        })

      %{merchant: merchant, doc: doc}
    end

    test "approves a document and records reviewer", %{doc: doc} do
      assert {:ok, reviewed} =
               Compliance.review_kyb_document(doc.id, "user:reviewer_1", %{
                 status: "approved",
                 reviewer_notes: "All checks passed"
               })

      assert reviewed.status == "approved"
      assert reviewed.reviewed_by == "user:reviewer_1"
      assert reviewed.reviewer_notes == "All checks passed"
      assert %DateTime{} = reviewed.reviewed_at
    end

    test "rejects a document with notes", %{doc: doc} do
      assert {:ok, reviewed} =
               Compliance.review_kyb_document(doc.id, "user:reviewer_2", %{
                 status: "rejected",
                 reviewer_notes: "Document expired"
               })

      assert reviewed.status == "rejected"
    end

    test "returns not_found for unknown document_id" do
      assert {:error, :not_found} =
               Compliance.review_kyb_document(Uniq.UUID.uuid7(), "user:rev", %{
                 status: "approved"
               })
    end

    test "rejects invalid status values", %{doc: doc} do
      assert {:error, %Ecto.Changeset{} = cs} =
               Compliance.review_kyb_document(doc.id, "user:rev", %{status: "pending_upload"})

      assert "is invalid" in errors_on(cs).status
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # KybDocument expanded fields
  # ──────────────────────────────────────────────────────────────────────────
  describe "upload_document/2 with new fields" do
    test "accepts label and required_for_business_types" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, doc} =
               Compliance.upload_document(merchant.public_id, %{
                 kind: "form_a",
                 label: "Form A — Sole Proprietorship Registration",
                 s3_key: "kyb/test/form_a.pdf",
                 checksum: "def456",
                 uploaded_by: "user:owner",
                 required_for_business_types: ["sole_proprietorship"]
               })

      assert doc.label == "Form A — Sole Proprietorship Registration"
      assert doc.status == "pending_upload"
      assert doc.required_for_business_types == ["sole_proprietorship"]
    end

    test "default status is pending_upload" do
      merchant = Fixtures.merchant_fixture()

      {:ok, doc} =
        Compliance.upload_document(merchant.public_id, %{
          kind: "id",
          s3_key: "kyb/test/id.pdf",
          checksum: "xyz",
          uploaded_by: "user:owner"
        })

      assert doc.status == "pending_upload"
      doc_from_db = Repo.get(KybDocument, doc.id)
      assert doc_from_db.status == "pending_upload"
    end

    test "accepts new document kinds" do
      merchant = Fixtures.merchant_fixture()

      for kind <- ~w[form_a certificate_of_incorporation business_registration
                     tax_clearance utility_bill bank_statement] do
        assert {:ok, doc} =
                 Compliance.upload_document(merchant.public_id, %{
                   kind: kind,
                   s3_key: "kyb/test/#{kind}.pdf",
                   checksum: "ck_#{kind}",
                   uploaded_by: "user:owner"
                 })

        assert doc.kind == kind
      end
    end
  end
end
