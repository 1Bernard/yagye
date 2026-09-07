defmodule YagyeCoreWeb.Controllers.PaymentLinks.PaymentLinkController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.PaymentLinks
  alias YagyeCoreWeb.ApiSpecs.PaymentLinkSpec
  alias YagyeCoreWeb.Controllers.PaymentLinks.PaymentLinkJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "payments:write"] when action in [:create, :deactivate]
  plug Authorize, [scope: "payments:read"] when action in [:index, :show]

  def open_api_operation(action), do: PaymentLinkSpec.operation(action)

  def create(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    attrs = Map.from_struct(conn.body_params)

    with {:ok, link} <- PaymentLinks.create_link(merchant_id, attrs) do
      Response.created(conn, PaymentLinkJSON.data(link))
    end
  end

  def index(conn, params) do
    merchant_id = conn.assigns.merchant_id
    active = params[:active] || params["active"]

    opts =
      cursor_opts(params) ++
        if(is_nil(active), do: [], else: [active: active])

    with {:ok, page} <- PaymentLinks.list_links(merchant_id, opts) do
      Response.ok(conn, PaymentLinkJSON.list(page))
    end
  end

  def show(conn, %{id: id}) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, link} <- PaymentLinks.get_link(id, merchant_id) do
      Response.ok(conn, PaymentLinkJSON.data(link))
    end
  end

  def deactivate(conn, %{id: id}) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, link} <- PaymentLinks.deactivate_link(id, merchant_id) do
      Response.ok(conn, PaymentLinkJSON.data(link))
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
end
