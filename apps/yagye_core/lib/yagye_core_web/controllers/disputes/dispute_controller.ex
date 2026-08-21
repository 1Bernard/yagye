defmodule YagyeCoreWeb.Controllers.Disputes.DisputeController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.{Disputes, Payments}
  alias YagyeCoreWeb.ApiSpecs.DisputeSpec
  alias YagyeCoreWeb.Controllers.Disputes.DisputeJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "payments:write"] when action in [:create]
  plug Authorize, [scope: "payments:read"] when action in [:show]

  def open_api_operation(:create), do: DisputeSpec.operation(:create_dispute)
  def open_api_operation(:show), do: DisputeSpec.operation(:show_dispute)

  def create(conn, %{payment_id: payment_id}) do
    attrs = Map.from_struct(conn.body_params)

    with {:ok, payment} <- Payments.get_payment(payment_id),
         {:ok, {dispute, _payment}} <- Disputes.create_dispute(payment, attrs) do
      Response.created(conn, DisputeJSON.data(dispute))
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, dispute} <- Disputes.get_dispute(id) do
      Response.ok(conn, DisputeJSON.data(dispute))
    end
  end
end
