defmodule YagyeCoreWeb.Controllers.Internal.ReceiptSettingsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def show(conn, %{"merchant_code" => merchant_code}) do
    with {:ok, settings} <- Merchants.get_receipt_settings(merchant_code) do
      Response.ok(conn, %{data: settings})
    end
  end

  def update(conn, %{"merchant_code" => merchant_code} = params) do
    settings = Map.get(params, "settings", %{})

    with {:ok, merchant} <- Merchants.update_receipt_settings(merchant_code, settings) do
      Response.ok(conn, %{data: merchant.receipt_settings})
    end
  end
end
