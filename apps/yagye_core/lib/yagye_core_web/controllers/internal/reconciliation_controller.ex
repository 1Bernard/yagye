defmodule YagyeCoreWeb.Controllers.Internal.ReconciliationController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Reconciliation
  alias YagyeCore.Repo
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def list_breaks(conn, %{"merchant_id" => merchant_code}) do
    with {:ok, merchant} <- resolve_merchant(merchant_code),
         {:ok, breaks} <- Reconciliation.list_breaks(merchant.id) do
      Response.ok(conn, %{
        object: "list",
        count: length(breaks),
        data: Enum.map(breaks, &break_json/1)
      })
    end
  end

  def list_all_breaks(conn, _params) do
    with {:ok, breaks} <- Reconciliation.list_all_breaks() do
      Response.ok(conn, %{
        object: "list",
        count: length(breaks),
        data: Enum.map(breaks, &break_json/1)
      })
    end
  end

  def get_break(conn, %{"id" => public_id}) do
    with {:ok, break} <- Reconciliation.get_break(public_id) do
      Response.ok(conn, break_json(break))
    end
  end

  def propose_adjustment(conn, %{"id" => public_id} = params) do
    proposed_action = %{
      "amount" => params["amount"],
      "direction" => params["direction"] || "credit_merchant",
      "resolution_code" => params["resolution_code"],
      "resolution_note" => params["resolution_note"]
    }

    with {:ok, approval} <-
           Reconciliation.propose_adjustment(public_id, params["proposed_by"], proposed_action) do
      Response.ok(conn, %{object: "adjustment_approval", id: approval.id, state: "pending"})
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────────────

  defp resolve_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  defp break_json(b) do
    %{
      object: "reconciliation_break",
      id: b.public_id,
      classification: b.classification,
      severity: b.severity,
      state: b.state,
      left_ref: b.left_ref,
      right_ref: b.right_ref,
      expected_amount: b.expected_amount,
      actual_amount: b.actual_amount,
      difference: b.difference,
      currency: b.currency,
      evidence: b.evidence || %{},
      assigned_to: b.assigned_to,
      resolution_code: b.resolution_code,
      resolution_note: b.resolution_note,
      detected_at: b.detected_at,
      resolved_at: b.resolved_at,
      sla_due_at: b.sla_due_at
    }
  end
end
