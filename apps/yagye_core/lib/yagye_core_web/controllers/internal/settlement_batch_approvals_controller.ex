defmodule YagyeCoreWeb.Controllers.Internal.SettlementBatchApprovalsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Settlement

  def approve(conn, %{"batch_id" => batch_id, "approved_by" => approver_code}) do
    case Settlement.approve_batch_dispatch(batch_id, approver_code) do
      {:ok, _batch} ->
        json(conn, %{status: "approved"})

      {:error, :not_awaiting_approval} ->
        conn |> put_status(409) |> json(%{error: "batch_not_awaiting_approval"})

      {:error, :unauthorized_approver} ->
        conn |> put_status(403) |> json(%{error: "not_an_authorized_approver"})

      {:error, :no_controls} ->
        conn |> put_status(422) |> json(%{error: "no_settlement_controls_configured"})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  def reject(conn, %{"batch_id" => batch_id, "rejected_by" => rejector_code} = params) do
    reason = params["reason"] || "Rejected by approver"

    case Settlement.reject_batch_dispatch(batch_id, rejector_code, reason) do
      {:ok, _batch} ->
        json(conn, %{status: "rejected"})

      {:error, :not_awaiting_approval} ->
        conn |> put_status(409) |> json(%{error: "batch_not_awaiting_approval"})

      {:error, :unauthorized_approver} ->
        conn |> put_status(403) |> json(%{error: "not_an_authorized_approver"})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end
end
