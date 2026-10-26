defmodule YagyeCoreWeb.Controllers.Internal.RefundApprovalsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  action_fallback YagyeCoreWeb.FallbackController

  alias YagyeCore.Disputes
  alias YagyeCore.Disputes.Schemas.Refund
  alias YagyeCore.Repo

  # POST /internal/refunds/:id/approve
  def approve(conn, %{"id" => refund_public_id} = params) do
    approved_by = params["approved_by"]
    reason = params["reason"]

    with {:ok, refund} <- fetch_pending_refund(refund_public_id),
         {:ok, updated} <- Disputes.approve_refund(refund, approved_by, reason) do
      conn
      |> put_status(200)
      |> json(%{
        id: updated.public_id,
        state: updated.state,
        approved_by: updated.approved_by,
        approved_at: updated.approved_at
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: %{code: "refund_not_found", message: "Refund not found."}})

      {:error, {:not_approvable, state}} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "not_approvable",
            message: "Refund cannot be approved in state: #{state}."
          }
        })

      {:error, %Ecto.Changeset{} = cs} ->
        errors = Ecto.Changeset.traverse_errors(cs, fn {msg, _opts} -> msg end)

        conn
        |> put_status(422)
        |> json(%{error: %{code: "validation_failed", errors: errors}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "approval_failed", message: inspect(reason)}})
    end
  end

  # POST /internal/refunds/:id/reject
  def reject(conn, %{"id" => refund_public_id} = params) do
    rejected_by = params["rejected_by"]
    reason = params["reason"] || "rejected_by_ops"

    with {:ok, refund} <- fetch_pending_refund(refund_public_id),
         {:ok, updated} <- Disputes.reject_refund(refund, rejected_by, reason) do
      conn
      |> put_status(200)
      |> json(%{
        id: updated.public_id,
        state: updated.state,
        failure_reason: updated.failure_reason
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: %{code: "refund_not_found", message: "Refund not found."}})

      {:error, {:not_rejectable, state}} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "not_rejectable",
            message: "Refund cannot be rejected in state: #{state}."
          }
        })

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "rejection_failed", message: inspect(reason)}})
    end
  end

  # GET /internal/refunds/pending
  def pending(conn, params) do
    opts = [limit: String.to_integer(params["limit"] || "50")]
    {:ok, page} = Disputes.get_pending_approval_refunds(opts)

    conn
    |> put_status(200)
    |> json(%{
      data: Enum.map(page.entries, &pending_refund_json/1),
      next_cursor: page.metadata.after
    })
  end

  defp fetch_pending_refund(public_id) do
    case Repo.get_by(Refund, public_id: public_id) do
      nil -> {:error, :not_found}
      refund -> {:ok, refund}
    end
  end

  defp pending_refund_json(refund) do
    %{
      id: refund.public_id,
      payment_id: refund.payment.public_id,
      amount: refund.amount,
      currency: refund.currency,
      reason: refund.reason,
      state: refund.state,
      initiated_by: refund.initiated_by,
      inserted_at: refund.inserted_at
    }
  end
end
