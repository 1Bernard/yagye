defmodule YagyeCore.Merchants.MerchantsTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Merchants

  describe "create_merchant/1" do
    test "creates a merchant with simulation mode" do
      assert {:ok, {merchant, _event}} =
               Merchants.create_merchant(%{
                 legal_name: "Acme Ltd",
                 trading_name: "Acme",
                 country: "gb",
                 default_currency: "gbp"
               })

      assert merchant.legal_name == "Acme Ltd"
      assert merchant.country == "GB"
      assert merchant.default_currency == "GBP"
      assert merchant.status == "registered"
      assert merchant.onboarding_state == "registered"
      assert String.starts_with?(merchant.public_id, "mch_")
      assert Merchants.live_mode_enabled?(merchant.id) == false
    end

    test "upcases country and currency" do
      {:ok, {merchant, _}} =
        Merchants.create_merchant(%{
          legal_name: "Test",
          trading_name: "Test",
          country: "us",
          default_currency: "usd"
        })

      assert merchant.country == "US"
      assert merchant.default_currency == "USD"
    end

    test "returns error on missing required fields" do
      assert {:error, changeset} = Merchants.create_merchant(%{legal_name: "No Country"})
      assert %{country: _, default_currency: _, trading_name: _} = errors_on(changeset)
    end
  end

  describe "submit_basic_info/2" do
    test "transitions onboarding_state to basic_info_submitted and sets tier 1" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, {updated, event}} =
               Merchants.submit_basic_info(merchant.public_id, "user:owner_001")

      assert updated.onboarding_state == "basic_info_submitted"
      assert updated.kyb_tier == 1
      assert event.merchant_id == merchant.id
      assert event.submitted_by == "user:owner_001"
    end

    test "returns invalid_state when not in registered state" do
      merchant = Fixtures.merchant_fixture()
      {:ok, _} = Merchants.submit_basic_info(merchant.public_id, "user:owner_001")

      assert {:error, :invalid_state} =
               Merchants.submit_basic_info(merchant.public_id, "user:owner_001")
    end

    test "returns not_found for unknown merchant" do
      assert {:error, :not_found} = Merchants.submit_basic_info("mch_ghost", "user:owner")
    end
  end

  describe "submit_documents/2" do
    test "transitions onboarding_state to documents_submitted and sets tier 2" do
      merchant = Fixtures.merchant_fixture()
      {:ok, {merchant, _}} = Merchants.submit_basic_info(merchant.public_id, "user:owner_001")

      assert {:ok, {updated, event}} =
               Merchants.submit_documents(merchant.public_id, "user:owner_001")

      assert updated.onboarding_state == "documents_submitted"
      assert updated.kyb_tier == 2
      assert event.submitted_by == "user:owner_001"
    end

    test "returns invalid_state when basic info has not been submitted" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, :invalid_state} =
               Merchants.submit_documents(merchant.public_id, "user:owner_001")
    end
  end

  describe "start_review/2" do
    test "transitions onboarding_state to under_review and records reviewed_by" do
      merchant = Fixtures.merchant_fixture()
      {:ok, {merchant, _}} = Merchants.submit_basic_info(merchant.public_id, "user:owner_001")
      {:ok, {merchant, _}} = Merchants.submit_documents(merchant.public_id, "user:owner_001")

      assert {:ok, {updated, event}} =
               Merchants.start_review(merchant.public_id, "user:compliance_001")

      assert updated.onboarding_state == "under_review"
      assert updated.reviewed_by == "user:compliance_001"
      assert updated.kyb_tier == 2
      assert event.reviewed_by == "user:compliance_001"
    end

    test "returns invalid_state when documents have not been submitted" do
      merchant = Fixtures.merchant_fixture()
      {:ok, {merchant, _}} = Merchants.submit_basic_info(merchant.public_id, "user:owner_001")

      assert {:error, :invalid_state} =
               Merchants.start_review(merchant.public_id, "user:compliance_001")
    end
  end

  describe "approve/2" do
    test "approves a merchant in under_review state and enables live mode" do
      merchant = Fixtures.merchant_fixture()
      {:ok, {merchant, _}} = Merchants.submit_basic_info(merchant.public_id, "user:owner_001")
      {:ok, {merchant, _}} = Merchants.submit_documents(merchant.public_id, "user:owner_001")
      {:ok, {merchant, _}} = Merchants.start_review(merchant.public_id, "user:compliance_001")

      assert {:ok, {approved, _event}} =
               Merchants.approve(merchant.public_id, "user:director_001")

      assert approved.status == "approved"
      assert approved.onboarding_state == "approved"
      assert approved.kyb_tier == 3
      assert approved.approved_by == "user:director_001"
      assert Merchants.live_mode_enabled?(approved.id) == true
    end

    test "returns not_kyb_ready when KYB steps are incomplete" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, :not_kyb_ready} = Merchants.approve(merchant.public_id, "user:director_001")
    end

    test "returns invalid_state when merchant is already approved" do
      merchant = Fixtures.approved_merchant_fixture()

      assert {:error, :invalid_state} = Merchants.approve(merchant.public_id, "user:director_001")
    end

    test "returns not_found for unknown public_id" do
      assert {:error, :not_found} = Merchants.approve("mch_nonexistent", "user:director_001")
    end
  end

  describe "check_live_capable?/1" do
    test "returns ok for a fully approved merchant" do
      merchant = Fixtures.approved_merchant_fixture()

      assert :ok = Merchants.check_live_capable?(merchant.id)
    end

    test "returns kyb_required for a merchant not yet approved" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, :kyb_required} = Merchants.check_live_capable?(merchant.id)
    end

    test "returns not_found for an unknown merchant id" do
      assert {:error, :not_found} =
               Merchants.check_live_capable?(Uniq.UUID.uuid7())
    end
  end

  describe "get_merchant/1" do
    test "returns merchant by public_id" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, found} = Merchants.get_merchant(merchant.public_id)
      assert found.id == merchant.id
    end

    test "returns not_found for unknown public_id" do
      assert {:error, :not_found} = Merchants.get_merchant("mch_doesnotexist")
    end
  end

  describe "issue_api_key/2" do
    test "issues a secret key and returns raw key once" do
      merchant = Fixtures.approved_merchant_fixture()

      assert {:ok, {api_key, raw_key, _event}} =
               Merchants.issue_api_key(merchant.public_id, %{
                 kind: "secret",
                 mode: "live",
                 scopes: ["merchants:read"]
               })

      assert api_key.kind == "secret"
      assert api_key.mode == :live
      assert api_key.merchant_id == merchant.id
      assert String.starts_with?(api_key.public_id, "key_")
      assert is_nil(api_key.revoked_at)
      assert String.length(raw_key) == 43
      assert String.slice(raw_key, 0, 24) == api_key.key_prefix
    end

    test "issues a publishable key with no secret hash" do
      merchant = Fixtures.approved_merchant_fixture()

      assert {:ok, {api_key, raw_key, _event}} =
               Merchants.issue_api_key(merchant.public_id, %{
                 kind: "publishable",
                 mode: "simulation",
                 scopes: []
               })

      assert api_key.kind == "publishable"
      assert is_nil(api_key.secret_hash)
      assert raw_key == api_key.key_prefix
    end

    test "returns not_found for unknown merchant" do
      assert {:error, :not_found} =
               Merchants.issue_api_key("mch_ghost", %{
                 kind: "secret",
                 mode: "simulation",
                 scopes: []
               })
    end
  end

  describe "authenticate/1" do
    test "authenticates a valid secret key" do
      merchant = Fixtures.approved_merchant_fixture()
      {_api_key, raw_key} = Fixtures.api_key_fixture(merchant)

      assert {:ok, authenticated_key} = Merchants.authenticate(raw_key)
      assert authenticated_key.merchant_id == merchant.id
    end

    test "authenticates a valid publishable key" do
      merchant = Fixtures.approved_merchant_fixture()

      {_api_key, raw_key} =
        Fixtures.api_key_fixture(merchant, %{kind: "publishable", mode: "simulation", scopes: []})

      assert {:ok, _} = Merchants.authenticate(raw_key)
    end

    test "rejects a wrong secret key with same prefix" do
      merchant = Fixtures.approved_merchant_fixture()
      {api_key, _raw_key} = Fixtures.api_key_fixture(merchant)

      wrong_key = api_key.key_prefix <> "AAAAAAAAAAAAAAAAAAA"
      assert {:error, :invalid_credentials} = Merchants.authenticate(wrong_key)
    end

    test "rejects a completely unknown key" do
      assert {:error, :invalid_credentials} =
               Merchants.authenticate("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    end

    test "rejects a revoked key" do
      merchant = Fixtures.approved_merchant_fixture()
      {api_key, raw_key} = Fixtures.api_key_fixture(merchant)

      {:ok, _} = Merchants.revoke_api_key(api_key.public_id, merchant.public_id, merchant.id)

      assert {:error, :invalid_credentials} = Merchants.authenticate(raw_key)
    end
  end

  describe "revoke_api_key/3" do
    test "revokes an active key" do
      merchant = Fixtures.approved_merchant_fixture()
      {api_key, _raw_key} = Fixtures.api_key_fixture(merchant)

      assert {:ok, {revoked, _event}} =
               Merchants.revoke_api_key(api_key.public_id, merchant.public_id, merchant.id)

      assert not is_nil(revoked.revoked_at)
    end

    test "returns not_found when key is already revoked" do
      merchant = Fixtures.approved_merchant_fixture()
      {api_key, _raw_key} = Fixtures.api_key_fixture(merchant)

      {:ok, _} = Merchants.revoke_api_key(api_key.public_id, merchant.public_id, merchant.id)

      assert {:error, :not_found} =
               Merchants.revoke_api_key(api_key.public_id, merchant.public_id, merchant.id)
    end

    test "returns not_found when key belongs to a different merchant" do
      merchant_a = Fixtures.approved_merchant_fixture()
      merchant_b = Fixtures.approved_merchant_fixture()
      {api_key, _} = Fixtures.api_key_fixture(merchant_a)

      assert {:error, :not_found} =
               Merchants.revoke_api_key(api_key.public_id, merchant_b.public_id, merchant_b.id)
    end
  end
end
