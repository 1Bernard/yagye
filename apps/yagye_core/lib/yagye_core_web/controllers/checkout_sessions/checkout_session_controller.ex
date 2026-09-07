defmodule YagyeCoreWeb.Controllers.CheckoutSessions.CheckoutSessionController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.CheckoutSessions
  alias YagyeCoreWeb.ApiSpecs.CheckoutSessionSpec
  alias YagyeCoreWeb.Controllers.CheckoutSessions.CheckoutSessionJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "payments:write"] when action in [:create, :expire]
  plug Authorize, [scope: "payments:read"] when action in [:index, :show]

  def open_api_operation(action), do: CheckoutSessionSpec.operation(action)

  def create(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    attrs = conn.body_params |> Map.from_struct() |> atomise_line_items()

    with {:ok, {session, url_token}} <- CheckoutSessions.create_session(merchant_id, attrs) do
      Response.created(conn, CheckoutSessionJSON.data(session, url_token))
    end
  end

  def index(conn, params) do
    merchant_id = conn.assigns.merchant_id

    opts =
      [
        state: params[:state] || params["state"],
        payment_link_id: params[:payment_link_id] || params["payment_link_id"]
      ]
      |> Keyword.reject(fn {_, v} -> is_nil(v) end)

    with {:ok, sessions} <- CheckoutSessions.list_sessions(merchant_id, opts) do
      Response.ok(conn, %{object: "list", data: Enum.map(sessions, &CheckoutSessionJSON.data/1)})
    end
  end

  def show(conn, %{id: id}) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, session} <- CheckoutSessions.get_session(id, merchant_id) do
      Response.ok(conn, CheckoutSessionJSON.data(session))
    end
  end

  def expire(conn, %{id: id}) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, session} <- CheckoutSessions.get_session(id, merchant_id),
         {:ok, expired} <- CheckoutSessions.expire_session(session) do
      Response.ok(conn, CheckoutSessionJSON.data(expired))
    end
  end

  defp atomise_line_items(%{line_items: items} = attrs) when is_list(items) do
    Map.put(
      attrs,
      :line_items,
      Enum.map(items, fn item ->
        if is_struct(item), do: Map.from_struct(item), else: item
      end)
    )
  end

  defp atomise_line_items(attrs), do: attrs
end
