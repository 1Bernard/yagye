defmodule YagyeCore.Fixtures do
  @moduledoc false

  alias YagyeCore.Merchants

  def merchant_fixture(attrs \\ %{}) do
    {:ok, {merchant, _}} =
      Merchants.create_merchant(
        Map.merge(
          %{
            legal_name: "Test Merchant #{System.unique_integer([:positive])}",
            trading_name: "Test Co",
            country: "GB",
            default_currency: "GBP"
          },
          attrs
        )
      )

    merchant
  end

  def approved_merchant_fixture(attrs \\ %{}) do
    merchant = merchant_fixture(attrs)
    {:ok, {merchant, _}} = Merchants.approve(merchant.public_id, merchant.id)
    merchant
  end

  # Returns {api_key, raw_key}. raw_key is only available at creation.
  def api_key_fixture(merchant, attrs \\ %{}) do
    {:ok, {api_key, raw_key, _}} =
      Merchants.issue_api_key(
        merchant.public_id,
        Map.merge(%{kind: "secret", mode: "simulation", scopes: ["*"]}, attrs)
      )

    {api_key, raw_key}
  end
end
