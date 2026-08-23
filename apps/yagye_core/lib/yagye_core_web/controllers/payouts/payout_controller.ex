defmodule YagyeCoreWeb.Controllers.Payouts.PayoutController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.Payouts
  alias YagyeCoreWeb.ApiSpecs.PayoutSpec
  alias YagyeCoreWeb.Controllers.Payouts.PayoutJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer

  plug Authorize, [scope: "payouts:write"] when action in [:create, :create_destination]

  plug Authorize,
       [scope: "payouts:read"]
       when action in [:index, :show, :destinations_index, :destinations_show]

  def open_api_operation(action), do: PayoutSpec.operation(action)

  def create(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    attrs = Map.from_struct(conn.body_params)

    with {:ok, payout} <- Payouts.create_payout(merchant_id, attrs) do
      Response.created(conn, PayoutJSON.data(payout))
    end
  end

  def index(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    payouts = Payouts.list_payouts(merchant_id)
    Response.ok(conn, PayoutJSON.list(payouts))
  end

  def show(conn, %{id: id}) do
    with {:ok, payout} <- Payouts.get_payout_by_public_id(id) do
      Response.ok(conn, PayoutJSON.data(payout))
    end
  end

  def create_destination(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    attrs = Map.from_struct(conn.body_params)

    with {:ok, destination} <- Payouts.create_destination(merchant_id, attrs) do
      Response.created(conn, PayoutJSON.destination_data(destination))
    end
  end

  def destinations_index(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    destinations = Payouts.list_destinations(merchant_id)
    Response.ok(conn, PayoutJSON.destination_list(destinations))
  end

  def destinations_show(conn, %{id: id}) do
    with {:ok, destination} <- Payouts.get_destination(id) do
      Response.ok(conn, PayoutJSON.destination_data(destination))
    end
  end
end
