defmodule YagyeCore.Merchants.MerchantKybTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Merchants
  alias YagyeCore.Merchants.Schemas.{MerchantAddress, MerchantContact}
  alias YagyeCore.Repo

  # ──────────────────────────────────────────────────────────────────────────
  # update_merchant_profile/2
  # ──────────────────────────────────────────────────────────────────────────
  describe "update_merchant_profile/2" do
    test "updates business classification fields" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, updated} =
               Merchants.update_merchant_profile(merchant.public_id, %{
                 business_type: "registered_business",
                 registration_type: "limited_liability",
                 category: "fintech",
                 tin: "C0001234567"
               })

      assert updated.business_type == "registered_business"
      assert updated.registration_type == "limited_liability"
      assert updated.category == "fintech"
      assert updated.tin == "C0001234567"
    end

    test "accepts partial updates" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, updated} =
               Merchants.update_merchant_profile(merchant.public_id, %{
                 business_type: "sole_proprietorship"
               })

      assert updated.business_type == "sole_proprietorship"
      assert is_nil(updated.registration_type)
    end

    test "returns not_found for unknown public_id" do
      assert {:error, :not_found} =
               Merchants.update_merchant_profile("mch_unknown", %{business_type: "individual"})
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # upsert_contact/2
  # ──────────────────────────────────────────────────────────────────────────
  describe "upsert_contact/2" do
    test "creates contact record for merchant" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, contact} =
               Merchants.upsert_contact(merchant.id, %{
                 general_email: "hello@example.com",
                 support_email: "support@example.com",
                 phone_number: "+233201234567"
               })

      assert contact.general_email == "hello@example.com"
      assert contact.merchant_id == merchant.id
    end

    test "updates existing contact on second call" do
      merchant = Fixtures.merchant_fixture()
      {:ok, _} = Merchants.upsert_contact(merchant.id, %{general_email: "first@example.com"})

      assert {:ok, updated} =
               Merchants.upsert_contact(merchant.id, %{
                 general_email: "updated@example.com",
                 twitter_handle: "@example"
               })

      assert updated.general_email == "updated@example.com"
      assert updated.twitter_handle == "@example"
      assert Repo.aggregate(MerchantContact, :count, :id) == 1
    end

    test "stores optional social handles" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, contact} =
               Merchants.upsert_contact(merchant.id, %{
                 facebook_username: "ExampleBiz",
                 instagram_handle: "@examplebiz",
                 whatsapp_number: "+233501234567",
                 whatsapp_label: "Customer Support"
               })

      assert contact.facebook_username == "ExampleBiz"
      assert contact.whatsapp_label == "Customer Support"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # upsert_address/3
  # ──────────────────────────────────────────────────────────────────────────
  describe "upsert_address/3" do
    test "creates office address" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, address} =
               Merchants.upsert_address(merchant.id, "office", %{
                 country: "GH",
                 city: "Accra",
                 street_address: "1 Independence Avenue",
                 gps_address: "GA-144-3422"
               })

      assert address.country == "GH"
      assert address.address_type == "office"
      assert address.gps_address == "GA-144-3422"
    end

    test "creates registered address separately from office address" do
      merchant = Fixtures.merchant_fixture()
      {:ok, _} = Merchants.upsert_address(merchant.id, "office", %{country: "GH", city: "Accra"})

      assert {:ok, registered} =
               Merchants.upsert_address(merchant.id, "registered", %{
                 country: "GH",
                 city: "Kumasi",
                 street_address: "5 Adum Road"
               })

      assert registered.address_type == "registered"
      assert Repo.aggregate(MerchantAddress, :count, :id) == 2
    end

    test "updates existing address on second call for same type" do
      merchant = Fixtures.merchant_fixture()

      {:ok, _} =
        Merchants.upsert_address(merchant.id, "office", %{country: "GH", city: "Accra"})

      assert {:ok, updated} =
               Merchants.upsert_address(merchant.id, "office", %{
                 country: "GH",
                 city: "Accra",
                 complex_building: "Heritage Tower, Floor 3"
               })

      assert updated.complex_building == "Heritage Tower, Floor 3"
      assert Repo.aggregate(MerchantAddress, :count, :id) == 1
    end

    test "rejects invalid address_type" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               Merchants.upsert_address(merchant.id, "invalid_type", %{country: "GH"})

      assert "is invalid" in errors_on(cs).address_type
    end
  end
end
