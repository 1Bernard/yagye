defmodule YagyeCoreWeb.Controllers.Invoices.InvoiceController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.Invoices
  alias YagyeCoreWeb.ApiSpecs.InvoiceSpec
  alias YagyeCoreWeb.Controllers.Invoices.InvoiceJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "invoices:write"] when action in [:create, :issue, :void]
  plug Authorize, [scope: "invoices:read"] when action in [:index, :show]

  def open_api_operation(action), do: InvoiceSpec.operation(action)

  def create(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    attrs = Map.from_struct(conn.body_params)

    line_items =
      (attrs[:line_items] || [])
      |> Enum.map(fn item ->
        m = if is_struct(item), do: Map.from_struct(item), else: item
        Map.take(m, [:description, :quantity, :unit_amount, :tax_rate_bps])
      end)

    with {:ok, invoice} <-
           Invoices.create_invoice(merchant_id, Map.put(attrs, :line_items, line_items)) do
      Response.created(conn, InvoiceJSON.data(invoice))
    end
  end

  def index(conn, params) do
    merchant_id = conn.assigns.merchant_id
    opts = cursor_opts(params) ++ [state: params[:state] || params["state"]]

    with {:ok, page} <- Invoices.list_invoices(merchant_id, opts) do
      Response.ok(conn, InvoiceJSON.list(page))
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, invoice} <- Invoices.get_invoice(id) do
      Response.ok(conn, InvoiceJSON.data(invoice))
    end
  end

  def issue(conn, %{id: id}) do
    with {:ok, invoice} <- Invoices.issue_invoice(id) do
      Response.ok(conn, InvoiceJSON.data(invoice))
    end
  end

  def void(conn, %{id: id}) do
    with {:ok, invoice} <- Invoices.void_invoice(id) do
      Response.ok(conn, InvoiceJSON.data(invoice))
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
