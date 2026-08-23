defmodule YagyeCoreWeb.Controllers.Settlement.SettlementController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.Settlement
  alias YagyeCoreWeb.ApiSpecs.SettlementSpec
  alias YagyeCoreWeb.Controllers.Settlement.SettlementJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer

  plug Authorize,
       [scope: "settlements:read"] when action in [:index, :show, :batch_index, :batch_show]

  def open_api_operation(action), do: SettlementSpec.operation(action)

  def index(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    settlements = Settlement.list_settlements(merchant_id)
    Response.ok(conn, SettlementJSON.list(settlements))
  end

  def show(conn, %{id: id}) do
    with {:ok, settlement} <- Settlement.get_settlement(id) do
      Response.ok(conn, SettlementJSON.data(settlement))
    end
  end

  def batch_index(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    batches = Settlement.list_batches(merchant_id)
    Response.ok(conn, SettlementJSON.batch_list(batches))
  end

  def batch_show(conn, %{id: id}) do
    case Settlement.get_batch(id) do
      nil -> {:error, :not_found}
      batch -> Response.ok(conn, SettlementJSON.batch_data(batch))
    end
  end
end
