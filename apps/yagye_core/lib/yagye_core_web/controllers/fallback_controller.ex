defmodule YagyeCoreWeb.FallbackController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias YagyeCoreWeb.Response

  def call(conn, {:error, :not_found}), do: Response.not_found(conn)

  def call(conn, {:error, {:not_disputable, state}}),
    do:
      Response.unprocessable(
        conn,
        "not_disputable",
        "Payment in state '#{state}' cannot be disputed"
      )

  def call(conn, {:error, {:not_refundable, state}}),
    do:
      Response.unprocessable(
        conn,
        "not_refundable",
        "Payment in state '#{state}' cannot be refunded"
      )

  def call(conn, {:error, :amount_exceeds_original}),
    do:
      Response.unprocessable(
        conn,
        "amount_exceeds_original",
        "Refund amount exceeds the original payment amount"
      )

  def call(conn, {:error, :amount_required}),
    do: Response.unprocessable(conn, "amount_required", "amount is required")

  def call(conn, {:error, :already_resolved}),
    do: Response.unprocessable(conn, "already_resolved", "Dispute has already been resolved")

  def call(conn, {:error, :invalid_state}),
    do:
      Response.unprocessable(
        conn,
        "invalid_state",
        "Resource is not in a state that allows this operation"
      )

  def call(conn, {:error, :invalid_onboarding_state}),
    do:
      Response.unprocessable(
        conn,
        "invalid_onboarding_state",
        "Onboarding is not in a submittable state"
      )

  def call(conn, {:error, changeset}), do: Response.validation_error(conn, changeset)
end
