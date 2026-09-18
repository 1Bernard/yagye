defmodule YagyeCoreWeb.Controllers.Internal.CheckoutSessionsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.CheckoutSessions, as: Checkout
  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Controllers.CheckoutSessions.CheckoutSessionJSON
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/checkout-sessions
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    opts =
      [state: params["state"], payment_link_id: params["payment_link_id"]]
      |> Keyword.reject(fn {_, v} -> is_nil(v) end)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, sessions} <- Checkout.list_sessions(merchant.id, opts) do
      data = Enum.map(sessions, &CheckoutSessionJSON.data/1)
      Response.ok(conn, %{object: "list", data: data, has_more: false})
    end
  end

  # GET /internal/checkout-sessions/:id
  def show(conn, %{"id" => id}) do
    with {:ok, session} <- Checkout.get_session_by_public_id(id) do
      Response.ok(conn, CheckoutSessionJSON.data(session))
    end
  end
end
