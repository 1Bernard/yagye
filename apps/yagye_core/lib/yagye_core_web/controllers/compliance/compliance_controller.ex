defmodule YagyeCoreWeb.Controllers.Compliance.ComplianceController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.{Compliance, Idempotency}
  alias YagyeCoreWeb.ApiSpecs.ComplianceSpec
  alias YagyeCoreWeb.Controllers.Compliance.ComplianceJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "kyb:write"] when action in [:submit_onboarding, :add_beneficial_owner, :upload_document]

  def open_api_operation(action), do: ComplianceSpec.operation(action)

  def submit_onboarding(conn, %{merchant_id: merchant_id}) do
    attrs = Map.from_struct(conn.body_params)
    with {:ok, {merchant, _event}} <- Compliance.submit_onboarding(merchant_id, attrs) do
      object = ComplianceJSON.onboarding_data(merchant)
      maybe_complete_idempotency(conn, 200, object, "merchant", merchant.id)
      Response.ok(conn, object)
    end
  end

  def add_beneficial_owner(conn, %{merchant_id: merchant_id}) do
    attrs = Map.from_struct(conn.body_params)
    with {:ok, {owner, _event}} <- Compliance.add_beneficial_owner(merchant_id, attrs) do
      object = ComplianceJSON.beneficial_owner_data(owner)
      maybe_complete_idempotency(conn, 201, object, "beneficial_owner", owner.id)
      Response.created(conn, object)
    end
  end

  def upload_document(conn, %{merchant_id: merchant_id}) do
    attrs = Map.from_struct(conn.body_params)
    with {:ok, {doc, _event}} <- Compliance.upload_document(merchant_id, attrs) do
      object = ComplianceJSON.document_data(doc)
      maybe_complete_idempotency(conn, 201, object, "kyb_document", doc.id)
      Response.created(conn, object)
    end
  end

  defp maybe_complete_idempotency(conn, status, body, type, id) do
    case conn.assigns[:idempotency_key] do
      nil -> :ok
      idem_key -> Idempotency.complete(idem_key.id, status, body, type, id)
    end
  end
end
