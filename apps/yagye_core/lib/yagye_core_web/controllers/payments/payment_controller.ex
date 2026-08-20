defmodule YagyeCoreWeb.Controllers.Payments.PaymentController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias OpenApiSpex.Plug.CastAndValidate
  alias YagyeCore.{Idempotency, Payments}
  alias YagyeCoreWeb.ApiSpecs.PaymentSpec
  alias YagyeCoreWeb.Controllers.Payments.PaymentJSON
  alias YagyeCoreWeb.Plugs.{Authorize, ValidationErrorRenderer}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  plug CastAndValidate, render_error: ValidationErrorRenderer
  plug Authorize, [scope: "payments:write"] when action in [:create]
  plug Authorize, [scope: "payments:read"] when action in [:show, :events]

  def open_api_operation(action), do: PaymentSpec.operation(action)

  def create(conn, _params) do
    merchant_id = conn.assigns.merchant_id
    attrs = Map.from_struct(conn.body_params)

    with {:ok, {payment, _event}} <- Payments.create_payment(merchant_id, attrs) do
      object = PaymentJSON.data(payment)
      maybe_complete_idempotency(conn, 201, object, "payment", payment.id)
      Response.created(conn, object)
    end
  end

  def show(conn, %{id: id}) do
    with {:ok, payment} <- Payments.get_payment(id) do
      Response.ok(conn, PaymentJSON.data(payment))
    end
  end

  def events(conn, %{id: id}) do
    with {:ok, payment} <- Payments.get_payment(id),
         {:ok, events} <- Payments.list_events(payment.id) do
      Response.ok(conn, PaymentJSON.event_list(events))
    end
  end

  defp maybe_complete_idempotency(conn, status, body, type, id) do
    case conn.assigns[:idempotency_key] do
      nil -> :ok
      idem_key -> Idempotency.complete(idem_key.id, status, body, type, id)
    end
  end
end
