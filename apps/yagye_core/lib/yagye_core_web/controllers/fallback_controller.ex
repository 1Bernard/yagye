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

  def call(conn, {:error, :unscreened_ubos}),
    do:
      Response.unprocessable(
        conn,
        "unscreened_ubos",
        "One or more beneficial owners with ≥25% ownership have not been cleared by AML screening"
      )

  def call(conn, {:error, :not_kyb_ready}),
    do: Response.unprocessable(conn, "kyb_incomplete", "KYB must be completed before approval")

  def call(conn, {:error, :already_inactive}),
    do:
      Response.unprocessable(conn, "already_inactive", "This reserve policy is already inactive")

  def call(conn, {:error, :already_approved}),
    do:
      Response.unprocessable(
        conn,
        "already_approved",
        "This reserve policy has already been approved"
      )

  def call(conn, {:error, :already_acknowledged}),
    do:
      Response.unprocessable(
        conn,
        "already_acknowledged",
        "This reserve policy has already been acknowledged"
      )

  def call(conn, {:error, :sod_violation}),
    do:
      Response.unprocessable(
        conn,
        "sod_violation",
        "The reviewer and approver must be different people"
      )

  def call(conn, {:error, :no_rejected_application}),
    do:
      Response.unprocessable(
        conn,
        "no_rejected_application",
        "No rejected application found for this merchant"
      )

  def call(conn, {:error, {:missing_param, field}}),
    do: Response.unprocessable(conn, "missing_param", "#{field} is required")

  def call(conn, {:error, :destination_required}),
    do: Response.unprocessable(conn, "missing_param", "destination_id is required")

  def call(conn, {:error, :insufficient_payable_balance}),
    do:
      Response.unprocessable(
        conn,
        "insufficient_balance",
        "Insufficient payable balance for this payout"
      )

  def call(conn, {:error, :destination_inactive}),
    do: Response.unprocessable(conn, "destination_inactive", "Payout destination is inactive")

  def call(conn, {:error, :destination_unverified}),
    do:
      Response.unprocessable(
        conn,
        "destination_unverified",
        "Payout destination has not been verified"
      )

  def call(conn, {:error, changeset}), do: Response.validation_error(conn, changeset)
end
