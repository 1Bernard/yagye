defmodule YagyeCoreWeb.Controllers.Disputes.RefundController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.{Disputes, Payments}
  alias YagyeCoreWeb.ApiSpecs.DisputeSpec
  alias YagyeCoreWeb.Controllers.Disputes.RefundJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "payments:write"] when action in [:create]
  plug Authorize, [scope: "payments:read"] when action in [:show]

  def open_api_operation(:create), do: DisputeSpec.operation(:create_refund)
  def open_api_operation(:show), do: DisputeSpec.operation(:show_refund)

  def create(conn, %{payment_id: payment_id}) do
    attrs = Map.from_struct(conn.body_params)

    with {:ok, payment} <- Payments.get_payment(payment_id),
         {:ok, {refund, _payment}} <- Disputes.create_refund(payment, attrs) do
      Response.created(conn, RefundJSON.data(refund))
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, refund} <- Disputes.get_refund(id) do
      Response.ok(conn, RefundJSON.data(refund))
    end
  end
end
