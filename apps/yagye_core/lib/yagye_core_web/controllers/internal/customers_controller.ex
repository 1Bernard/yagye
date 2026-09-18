defmodule YagyeCoreWeb.Controllers.Internal.CustomersController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Customers
  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Controllers.Customers.CustomerJSON
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/customers
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    opts =
      [limit: params["limit"], starting_after: params["starting_after"]]
      |> Keyword.reject(fn {_, v} -> is_nil(v) end)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, page} <- Customers.list_customers(merchant.id, opts) do
      Response.ok(conn, CustomerJSON.list(page))
    end
  end

  # GET /internal/customers/:id
  def show(conn, %{"id" => id}) do
    with {:ok, customer} <- Customers.get_customer(id) do
      Response.ok(conn, CustomerJSON.data(customer))
    end
  end
end
