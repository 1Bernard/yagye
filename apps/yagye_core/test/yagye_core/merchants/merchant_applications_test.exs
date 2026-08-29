defmodule YagyeCore.Merchants.MerchantApplicationsTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Merchants
  alias YagyeCore.Merchants.Schemas.MerchantMode
  alias YagyeCore.Repo

  @valid_attrs %{
    first_name: "Kwame",
    last_name: "Asante",
    email: "kwame@example.com",
    phone_number: "+233201234567",
    job_title: "CEO",
    legal_name: "Asante Tech Ltd",
    trading_name: "AsTech",
    country: "GH",
    default_currency: "GHS",
    industry: "fintech",
    employee_range: "11-50",
    annual_tpv_estimate_cents: 500_000_000,
    website_url: "https://astech.gh",
    use_case: "Mobile money collection for SaaS subscriptions",
    expected_methods: ["mtn_momo", "airtel_tigo"]
  }

  describe "submit_application/1" do
    test "creates an application with submitted status" do
      assert {:ok, {application, event}} = Merchants.submit_application(@valid_attrs)

      assert application.status == "submitted"
      assert application.email == "kwame@example.com"
      assert application.legal_name == "Asante Tech Ltd"
      assert application.country == "GH"
      assert application.default_currency == "GHS"
      assert String.starts_with?(application.public_id, "app_")
      assert application.expected_methods == ["mtn_momo", "airtel_tigo"]

      assert event.application_id == application.id
      assert event.public_id == application.public_id
      assert event.email == "kwame@example.com"
    end

    test "lowercases and trims email on insert" do
      attrs = Map.put(@valid_attrs, :email, "  Kwame@Example.COM  ")
      {:ok, {application, _event}} = Merchants.submit_application(attrs)
      assert application.email == "kwame@example.com"
    end

    test "upcases country and currency" do
      attrs =
        Map.merge(@valid_attrs, %{
          country: "gh",
          default_currency: "ghs",
          email: "unique@test.com"
        })

      {:ok, {application, _event}} = Merchants.submit_application(attrs)
      assert application.country == "GH"
      assert application.default_currency == "GHS"
    end

    test "returns error when required fields are missing" do
      assert {:error, changeset} = Merchants.submit_application(%{legal_name: "Partial"})
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :first_name)
      assert Map.has_key?(errors, :last_name)
      assert Map.has_key?(errors, :email)
      assert Map.has_key?(errors, :country)
    end

    test "returns error for invalid email format" do
      attrs = Map.put(@valid_attrs, :email, "not-an-email")
      assert {:error, changeset} = Merchants.submit_application(attrs)
      assert %{email: _} = errors_on(changeset)
    end
  end

  describe "start_application_review/2" do
    test "transitions status to under_review and records reviewer" do
      {:ok, {application, _}} = Merchants.submit_application(@valid_attrs)

      assert {:ok, {updated, event}} =
               Merchants.start_application_review(
                 application.public_id,
                 "user:ops_analyst_001",
                 "Looks promising, proceeding with review."
               )

      assert updated.status == "under_review"
      assert updated.reviewed_by == "user:ops_analyst_001"
      assert updated.review_notes == "Looks promising, proceeding with review."
      assert updated.reviewed_at != nil
      assert event.application_id == application.id
      assert event.reviewed_by == "user:ops_analyst_001"
    end

    test "returns invalid_state when application is already under review" do
      {:ok, {application, _}} = Merchants.submit_application(@valid_attrs)
      {:ok, _} = Merchants.start_application_review(application.public_id, "user:analyst_001")

      assert {:error, :invalid_state} =
               Merchants.start_application_review(application.public_id, "user:analyst_002")
    end

    test "returns invalid_state when application is approved" do
      {:ok, {application, _}} = application_under_review()

      Merchants.approve_application(application.public_id, "user:manager_001")

      assert {:error, :invalid_state} =
               Merchants.start_application_review(application.public_id, "user:analyst_new")
    end

    test "returns not_found for unknown application" do
      assert {:error, :not_found} =
               Merchants.start_application_review("app_ghost", "user:analyst_001")
    end
  end

  describe "approve_application/2" do
    test "approves the application and creates a merchant" do
      {:ok, {application, _}} = application_under_review(reviewed_by: "user:analyst_001")

      assert {:ok, {approved_app, merchant, event}} =
               Merchants.approve_application(application.public_id, "user:manager_001")

      assert approved_app.status == "approved"
      assert approved_app.approved_by == "user:manager_001"
      assert approved_app.merchant_id == merchant.id

      assert merchant.legal_name == application.legal_name
      assert merchant.country == application.country
      assert merchant.default_currency == application.default_currency
      assert merchant.status == "registered"
      assert String.starts_with?(merchant.public_id, "mch_")

      assert event.application_id == application.id
      assert event.merchant_public_id == merchant.public_id
    end

    test "new merchant gets simulation mode enabled" do
      {:ok, {application, _}} = application_under_review(reviewed_by: "user:analyst_001")

      {:ok, {_, merchant, _}} =
        Merchants.approve_application(application.public_id, "user:manager_001")

      assert Merchants.live_mode_enabled?(merchant.id) == false

      # simulation mode should be granted
      import Ecto.Query

      count =
        Repo.aggregate(
          from(m in MerchantMode,
            where: m.merchant_id == ^merchant.id and m.mode == :simulation
          ),
          :count
        )

      assert count == 1
    end

    test "rejects SoD violation when approver equals reviewer" do
      {:ok, {application, _}} = application_under_review(reviewed_by: "user:same_person")

      assert {:error, :sod_violation} =
               Merchants.approve_application(application.public_id, "user:same_person")
    end

    test "returns invalid_state when application is still submitted" do
      {:ok, {application, _}} = Merchants.submit_application(@valid_attrs)

      assert {:error, :invalid_state} =
               Merchants.approve_application(application.public_id, "user:manager_001")
    end

    test "returns not_found for unknown application" do
      assert {:error, :not_found} =
               Merchants.approve_application("app_ghost", "user:manager_001")
    end
  end

  describe "reject_application/2" do
    test "rejects a submitted application" do
      {:ok, {application, _}} = Merchants.submit_application(@valid_attrs)

      assert {:ok, {rejected, event}} =
               Merchants.reject_application(
                 application.public_id,
                 "user:analyst_001",
                 "Business type not supported in current markets."
               )

      assert rejected.status == "rejected"
      assert rejected.rejected_reason == "Business type not supported in current markets."
      assert event.rejected_by == "user:analyst_001"
      assert event.reason == "Business type not supported in current markets."
    end

    test "rejects an under_review application" do
      {:ok, {application, _}} = application_under_review()

      assert {:ok, {rejected, _event}} =
               Merchants.reject_application(
                 application.public_id,
                 "user:manager_001",
                 "Failed AML screening."
               )

      assert rejected.status == "rejected"
    end

    test "returns invalid_state when application is already approved" do
      {:ok, {application, _}} = application_under_review(reviewed_by: "user:analyst_001")
      {:ok, _} = Merchants.approve_application(application.public_id, "user:manager_001")

      assert {:error, :invalid_state} =
               Merchants.reject_application(
                 application.public_id,
                 "user:analyst_002",
                 "Too late."
               )
    end

    test "returns not_found for unknown application" do
      assert {:error, :not_found} =
               Merchants.reject_application("app_ghost", "user:analyst_001", "reason")
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp unique_email, do: "applicant_#{System.unique_integer([:positive])}@example.com"

  defp application_under_review(opts \\ []) do
    reviewed_by =
      Keyword.get(opts, :reviewed_by, "user:analyst_#{System.unique_integer([:positive])}")

    attrs = Map.put(@valid_attrs, :email, unique_email())
    {:ok, {application, _}} = Merchants.submit_application(attrs)

    {:ok, {under_review, _}} =
      Merchants.start_application_review(application.public_id, reviewed_by)

    {:ok, {under_review, nil}}
  end
end
