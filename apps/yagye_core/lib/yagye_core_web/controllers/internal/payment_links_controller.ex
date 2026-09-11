defmodule YagyeCoreWeb.Controllers.Internal.PaymentLinksController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.PaymentLinks
  alias YagyeCoreWeb.Controllers.PaymentLinks.PaymentLinkJSON

  action_fallback YagyeCoreWeb.FallbackController

  # PATCH /internal/payment-links/:public_id/checkout-layout
  # Body: { merchant_code, layout }
  def update_checkout_layout(conn, %{"public_id" => public_id} = params) do
    merchant_code = params["merchant_code"]
    layout = params["layout"] || %{}

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, link} <- PaymentLinks.update_checkout_layout(public_id, merchant.id, layout) do
      conn
      |> put_status(:ok)
      |> json(PaymentLinkJSON.data(link))
    end
  end

  # GET /internal/payment-links?merchant_code=:code
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      opts = cursor_opts(params)
      {:ok, page} = PaymentLinks.list_links(merchant.id, opts)

      conn
      |> put_status(:ok)
      |> json(PaymentLinkJSON.list(page))
    end
  end

  # POST /internal/payment-links
  # Body: { merchant_code, kind, currency, description, ... }
  @allowed_create_fields ~w[kind currency description amount reusable
                             collect_email collect_phone collect_name
                             image_url allowed_methods max_uses expires_at metadata]

  def create(conn, %{"merchant_code" => merchant_code} = params) do
    attrs =
      Map.take(params, @allowed_create_fields)
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, link} <- PaymentLinks.create_link(merchant.id, attrs) do
      conn
      |> put_status(:created)
      |> json(PaymentLinkJSON.data(link))
    end
  end

  defp cursor_opts(params) do
    [
      limit: params["limit"],
      starting_after: params["starting_after"]
    ]
    |> Keyword.reject(fn {_, v} -> is_nil(v) end)
  end
end
