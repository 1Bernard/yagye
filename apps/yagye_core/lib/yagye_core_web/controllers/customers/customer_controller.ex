defmodule YagyeCoreWeb.Controllers.Customers.CustomerController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.Customers
  alias YagyeCoreWeb.ApiSpecs.CustomerSpec
  alias YagyeCoreWeb.Controllers.Customers.CustomerJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer

  plug Authorize,
       [scope: "customers:read"]
       when action in [:index, :show, :verifications_index, :verifications_show]

  def open_api_operation(action), do: CustomerSpec.operation(action)

  def index(conn, params) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, page} <- Customers.list_customers(merchant_id, cursor_opts(params)) do
      Response.ok(conn, CustomerJSON.list(page))
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, customer} <- Customers.get_customer(id) do
      Response.ok(conn, CustomerJSON.data(customer))
    end
  end

  def verifications_index(conn, params) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, page} <- Customers.list_account_verifications(merchant_id, cursor_opts(params)) do
      Response.ok(conn, CustomerJSON.verification_list(page))
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

  def verifications_show(conn, %{id: id}) do
    with {:ok, verification} <- Customers.get_account_verification(id) do
      Response.ok(conn, CustomerJSON.verification_data(verification))
    end
  end
end
