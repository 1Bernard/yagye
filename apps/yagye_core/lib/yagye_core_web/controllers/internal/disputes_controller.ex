defmodule YagyeCoreWeb.Controllers.Internal.DisputesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Disputes

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
