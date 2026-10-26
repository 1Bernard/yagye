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

  @allowed_config_fields ~w[allowed_methods logo_url display_name brand_colour default_locale
                             support_email support_phone website_url terms_url privacy_url
                             refund_policy_url refund_window_days partial_refunds_enabled
                             requires_approval_above_pesewas]a

  # PATCH /internal/merchants/:merchant_code/checkout-config
  def update(conn, %{"merchant_code" => merchant_code} = params) do
    attrs =
      @allowed_config_fields
      |> Enum.flat_map(fn key ->
        str = Atom.to_string(key)
        if Map.has_key?(params, str), do: [{key, params[str]}], else: []
      end)
      |> Map.new()

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, config} <- CheckoutSessions.update_checkout_config(merchant.id, attrs) do
      Response.ok(conn, render_config(config))
    end
  end

  # PATCH /internal/merchants/:merchant_code/checkout-config/logo
  def update_logo(conn, %{"merchant_code" => merchant_code} = params) do
    logo_url = params["logo_url"]

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, config} <-
           CheckoutSessions.update_checkout_logo(merchant.id, logo_url, merchant.trading_name) do
      Response.ok(conn, render_config(config))
    end
  end

  defp render_config(config) do
    %{
      allowed_methods: config.allowed_methods,
      display_name: config.display_name,
      brand_colour: config.brand_colour,
      logo_url: config.logo_url,
      default_locale: config.default_locale,
      refund_window_days: config.refund_window_days,
      partial_refunds_enabled: config.partial_refunds_enabled,
      requires_approval_above_pesewas: config.requires_approval_above_pesewas
    }
  end
end
