defmodule YagyeCoreWeb.Controllers.Internal.CheckoutConfigController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.CheckoutSessions
  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/checkout-config
  def show(conn, %{"merchant_code" => merchant_code}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, config} <- CheckoutSessions.get_checkout_config(merchant.id) do
      Response.ok(conn, render_config(config))
    end
  end

  # PATCH /internal/merchants/:merchant_code/checkout-config
  def update(conn, %{"merchant_code" => merchant_code} = params) do
    attrs = %{}

    attrs =
      if params["allowed_methods"],
        do: Map.put(attrs, :allowed_methods, params["allowed_methods"]),
        else: attrs

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, config} <- CheckoutSessions.update_checkout_config(merchant.id, attrs) do
      Response.ok(conn, render_config(config))
    end
  end

  defp render_config(config) do
    %{
      allowed_methods: config.allowed_methods,
      display_name: config.display_name,
      brand_colour: config.brand_colour,
      logo_url: config.logo_url,
      default_locale: config.default_locale
    }
  end
end
