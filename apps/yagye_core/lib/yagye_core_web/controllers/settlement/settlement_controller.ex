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

  def index(conn, params) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, page} <- Settlement.list_settlements(merchant_id, cursor_opts(params)) do
      Response.ok(conn, SettlementJSON.list(page))
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, settlement} <- Settlement.get_settlement(id) do
      Response.ok(conn, SettlementJSON.data(settlement))
    end
  end

  def batch_index(conn, params) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, page} <- Settlement.list_batches(merchant_id, cursor_opts(params)) do
      Response.ok(conn, SettlementJSON.batch_list(page))
    end
  end

  defp cursor_opts(params) do
    [
      limit: params["limit"] || params[:limit],
      starting_after: params["starting_after"] || params[:starting_after],
      ending_before: params["ending_before"] || params[:ending_before]
    ]
    |> Keyword.reject(fn {_, v} -> is_nil(v) end)
  end

  def batch_show(conn, %{id: id}) do
    case Settlement.get_batch(id) do
      nil -> {:error, :not_found}
      batch -> Response.ok(conn, SettlementJSON.batch_data(batch))
    end
  end
end
