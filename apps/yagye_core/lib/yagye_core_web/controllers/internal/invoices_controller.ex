defmodule YagyeCoreWeb.Controllers.Internal.InvoicesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Invoices
  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Controllers.Invoices.InvoiceJSON
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/invoices
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    opts =
      [state: params["state"], limit: params["limit"], starting_after: params["starting_after"]]
      |> Keyword.reject(fn {_, v} -> is_nil(v) end)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, page} <- Invoices.list_invoices(merchant.id, opts) do
      Response.ok(conn, InvoiceJSON.list(page))
    end
  end

  # GET /internal/invoices/:id
  def show(conn, %{"id" => id}) do
    with {:ok, invoice} <- Invoices.get_invoice(id) do
      Response.ok(conn, InvoiceJSON.data(invoice))
    end
  end

  @allowed_create_fields ~w[customer_reference number currency issue_date due_date
                             notes terms payment_link_id line_items]

  # POST /internal/invoices
  def create(conn, %{"merchant_code" => merchant_code} = params) do
    line_items =
      (params["line_items"] || [])
      |> Enum.map(fn item ->
        Map.take(item, ["description", "quantity", "unit_amount", "tax_rate_bps"])
        |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      end)

    attrs =
      Map.take(params, @allowed_create_fields)
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:line_items, line_items)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, invoice} <- Invoices.create_invoice(merchant.id, attrs) do
      Response.created(conn, InvoiceJSON.data(invoice))
    end
  end

  @allowed_update_fields ~w[customer_reference number currency issue_date due_date notes terms line_items]

  # PATCH /internal/invoices/:id
  def update(conn, %{"id" => id} = params) do
    line_items =
      (params["line_items"] || [])
      |> Enum.map(fn item ->
        Map.take(item, ["description", "quantity", "unit_amount", "tax_rate_bps"])
        |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      end)

    attrs =
      Map.take(params, @allowed_update_fields)
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:line_items, line_items)

    with {:ok, invoice} <- Invoices.update_invoice(id, attrs) do
      Response.ok(conn, InvoiceJSON.data(invoice))
    end
  end

  # POST /internal/invoices/:id/issue
  def issue(conn, %{"id" => id} = params) do
    allowed_methods =
      params
      |> Map.get("allowed_methods", ["mobile_money"])
      |> List.wrap()
      |> Enum.filter(&(&1 in ~w[mobile_money card bank_transfer]))

    payment_config = %{
      allowed_methods: allowed_methods,
      collect_email: params["collect_email"] == true || params["collect_email"] == "true",
      collect_phone: params["collect_phone"] == true || params["collect_phone"] == "true",
      collect_name: params["collect_name"] == true || params["collect_name"] == "true"
    }

    with {:ok, invoice} <- Invoices.issue_invoice(id, payment_config) do
      Response.ok(conn, InvoiceJSON.data(invoice))
    end
  end

  # POST /internal/invoices/:id/void
  def void(conn, %{"id" => id}) do
    with {:ok, invoice} <- Invoices.void_invoice(id) do
      Response.ok(conn, InvoiceJSON.data(invoice))
    end
  end
end
