defmodule YagyeCoreWeb.Controllers.ApiKeys.ApiKeyController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.{Idempotency, Merchants}
  alias YagyeCoreWeb.ApiSpecs.ApiKeySpec
  alias YagyeCoreWeb.Controllers.ApiKeys.ApiKeyJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "api_keys:write"] when action in [:create, :delete]

  def open_api_operation(action), do: ApiKeySpec.operation(action)

  def create(conn, %{merchant_id: merchant_id}) do
    with {:ok, {api_key, raw_key, _event}} <- Merchants.issue_api_key(merchant_id, Map.from_struct(conn.body_params)) do
      object = ApiKeyJSON.data(api_key, raw_key)
      maybe_complete_idempotency(conn, 201, object, "api_key", api_key.id)
      Response.created(conn, object)
    end
  end

  def delete(conn, %{merchant_id: merchant_id, id: key_id}) do
    revoked_by = conn.assigns.merchant_id

    with {:ok, {api_key, _event}} <- Merchants.revoke_api_key(key_id, merchant_id, revoked_by) do
      Response.ok(conn, ApiKeyJSON.data(api_key))
    end
  end

  defp maybe_complete_idempotency(conn, status, body, type, id) do
    case conn.assigns[:idempotency_key] do
      nil -> :ok
      idem_key -> Idempotency.complete(idem_key.id, status, body, type, id)
    end
  end
end
