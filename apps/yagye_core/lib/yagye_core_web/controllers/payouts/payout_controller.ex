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
    mode = to_string(conn.assigns.mode)
    raw = body_to_map(conn.body_params)

    with {:ok, dest} <- resolve_destination(merchant_id, raw["destination_id"]) do
      attrs = %{
        mode: mode,
        amount: raw["amount"],
        currency: raw["currency"] || "GHS",
        destination_id: dest.id,
        destination_type: dest.kind,
        destination_fingerprint: dest.fingerprint,
        scheduled_for: raw["scheduled_for"],
        requested_by: raw["requested_by"]
      }

      with {:ok, payout} <- Payouts.create_payout(merchant_id, attrs) do
        Response.created(conn, PayoutJSON.data(payout))
      end
    end
  end

  defp resolve_destination(_merchant_id, nil), do: {:error, :destination_required}

  defp resolve_destination(merchant_id, public_id) do
    case Payouts.get_destination_by_public_id(public_id) do
      {:ok, dest} when dest.merchant_id == merchant_id -> {:ok, dest}
      {:ok, _} -> {:error, :not_found}
      err -> err
    end
  end

  def index(conn, params) do
    merchant_id = conn.assigns.merchant_id

    with {:ok, page} <- Payouts.list_payouts(merchant_id, cursor_opts(params)) do
      Response.ok(conn, PayoutJSON.list(page))
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, payout} <- Payouts.get_payout_by_public_id(id) do
      Response.ok(conn, PayoutJSON.data(payout))
    end
  end

  def create_destination(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    attrs = body_to_map(conn.body_params)

    with {:ok, destination} <- Payouts.create_destination(merchant_id, attrs) do
      Response.created(conn, PayoutJSON.destination_data(destination))
    end
  end

  def destinations_index(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    destinations = Payouts.list_destinations(merchant_id)
    Response.ok(conn, PayoutJSON.destination_list(destinations))
  end

  defp cursor_opts(params) do
    [
      limit: params["limit"] || params[:limit],
      starting_after: params["starting_after"] || params[:starting_after],
      ending_before: params["ending_before"] || params[:ending_before]
    ]
    |> Keyword.reject(fn {_, v} -> is_nil(v) end)
  end

  def destinations_show(conn, %{id: id}) do
    with {:ok, destination} <- Payouts.get_destination(id) do
      Response.ok(conn, PayoutJSON.destination_data(destination))
    end
  end

  # OpenApiSpex casts body_params to a struct only when the spec defines a named schema.
  # The payout spec uses a generic object schema, so body_params stays a plain map.
  defp body_to_map(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp body_to_map(map) when is_map(map), do: map
end
