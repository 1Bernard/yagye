defmodule YagyeCoreWeb.Controllers.Merchants.MerchantController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.{Idempotency, Merchants}
  alias YagyeCoreWeb.ApiSpecs.MerchantSpec
  alias YagyeCoreWeb.Controllers.Merchants.MerchantJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "merchants:write"] when action in [:create]
  plug Authorize, [scope: "merchants:read"] when action in [:show]
  plug Authorize, [scope: "merchants:admin"] when action in [:approve]

  def open_api_operation(action), do: MerchantSpec.operation(action)

  def create(conn, _params) do
    with {:ok, {merchant, _event}} <- Merchants.create_merchant(Map.from_struct(conn.body_params)) do
      object = MerchantJSON.data(merchant)
      maybe_complete_idempotency(conn, 201, object, "merchant", merchant.id)
      Response.created(conn, object)
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, merchant} <- Merchants.get_merchant(id) do
      Response.ok(conn, MerchantJSON.data(merchant))
    end
  end

  def approve(conn, %{merchant_id: merchant_id}) do
    approved_by = conn.assigns.merchant_id

    with {:ok, {merchant, _event}} <- Merchants.approve(merchant_id, approved_by) do
      object = MerchantJSON.data(merchant)
      maybe_complete_idempotency(conn, 200, object, "merchant", merchant.id)
      Response.ok(conn, object)
    end
  end

  defp maybe_complete_idempotency(conn, status, body, type, id) do
    case conn.assigns[:idempotency_key] do
      nil -> :ok
      idem_key -> Idempotency.complete(idem_key.id, status, body, type, id)
    end
  end
end
