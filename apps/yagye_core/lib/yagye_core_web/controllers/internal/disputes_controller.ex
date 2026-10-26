defmodule YagyeCoreWeb.Controllers.Internal.DisputesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  action_fallback YagyeCoreWeb.FallbackController

  alias YagyeCore.{Disputes, Payments}

  # POST /internal/payments/:payment_id/disputes
  # Used by ops to record a chargeback notification received from a network.
  def create(conn, %{"payment_id" => payment_public_id} = params) do
    attrs = %{
      reason: params["reason"] || "chargeback",
      network: params["network"] || "unknown",
      amount: params["amount"] && String.to_integer(to_string(params["amount"])),
      currency: params["currency"]
    }

    with {:ok, payment} <- Payments.get_payment(payment_public_id),
         {:ok, {dispute, _payment}} <- Disputes.create_dispute(payment, attrs) do
      conn
      |> put_status(201)
      |> json(%{
        id: dispute.public_id,
        payment_id: payment_public_id,
        stage: dispute.stage,
        reason: dispute.reason,
        network: dispute.network,
        amount: dispute.amount,
        currency: dispute.currency
      })
    else
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "payment_not_found"})

      {:error, {:not_disputable, state}} ->
        conn |> put_status(422) |> json(%{error: "not_disputable", state: state})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  def submit_evidence(conn, %{"id" => public_id}) do
    with {:ok, dispute} <- Disputes.get_dispute(public_id),
         {:ok, updated} <- Disputes.submit_evidence(dispute) do
      json(conn, %{status: "ok", stage: updated.stage})
    else
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "dispute_not_found"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  def resolve(conn, %{"id" => public_id, "outcome" => outcome_str}) do
    outcome = String.to_existing_atom(outcome_str)

    with {:ok, dispute} <- Disputes.get_dispute(public_id),
         {:ok, {resolved, _payment}} <- Disputes.resolve_dispute(dispute, outcome) do
      json(conn, %{status: "ok", outcome: resolved.outcome, stage: resolved.stage})
    else
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "dispute_not_found"})

      {:error, :already_resolved} ->
        conn |> put_status(409) |> json(%{error: "dispute_already_resolved"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  rescue
    ArgumentError ->
      conn |> put_status(422) |> json(%{error: "invalid_outcome"})
  end
end
