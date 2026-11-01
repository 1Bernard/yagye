defmodule YagyeCore.Merchants.ReceiptSettingsTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Merchants

  describe "get_receipt_settings/1" do
    test "returns empty map by default for a new merchant" do
      merchant = Fixtures.merchant_fixture()
      assert {:ok, settings} = Merchants.get_receipt_settings(merchant.public_id)
      assert settings == %{}
    end

    test "returns error for unknown merchant code" do
      assert {:error, :not_found} = Merchants.get_receipt_settings("mch_nonexistent")
    end
  end

  describe "update_receipt_settings/2" do
    test "updates receipt settings with valid keys" do
      merchant = Fixtures.merchant_fixture()

      settings = %{
        "show_fee" => true,
        "show_powered_by" => false,
        "custom_note" => "Thank you for your payment!"
      }

      assert {:ok, updated} = Merchants.update_receipt_settings(merchant.public_id, settings)
      assert updated.receipt_settings["show_fee"] == true
      assert updated.receipt_settings["show_powered_by"] == false
      assert updated.receipt_settings["custom_note"] == "Thank you for your payment!"
    end

    test "strips unknown keys from settings" do
      merchant = Fixtures.merchant_fixture()

      settings = %{
        "show_fee" => true,
        "evil_key" => "should be dropped",
        "another_bad_key" => 999
      }

      assert {:ok, updated} = Merchants.update_receipt_settings(merchant.public_id, settings)
      assert updated.receipt_settings["show_fee"] == true
      refute Map.has_key?(updated.receipt_settings, "evil_key")
      refute Map.has_key?(updated.receipt_settings, "another_bad_key")
    end

    test "persists changes across fetches" do
      merchant = Fixtures.merchant_fixture()

      Merchants.update_receipt_settings(merchant.public_id, %{"show_fee" => true})
      assert {:ok, settings} = Merchants.get_receipt_settings(merchant.public_id)
      assert settings["show_fee"] == true
    end

    test "returns error for unknown merchant code" do
      assert {:error, :not_found} =
               Merchants.update_receipt_settings("mch_nonexistent", %{"show_fee" => true})
    end
  end
end
