defmodule YagyeCoreWeb.Controllers.Disputes.DisputeJSON do
  @moduledoc false

  alias YagyeCore.Disputes.Schemas.Dispute

  def data(%Dispute{} = d) do
    %{
      id: d.public_id,
      object: "dispute",
      payment_id: d.payment_id,
      network: d.network,
      reason: d.reason,
      amount: d.amount,
      currency: d.currency,
      stage: d.stage,
      outcome: d.outcome,
      evidence_due_at: d.evidence_due_at,
      resolved_at: d.resolved_at,
      metadata: d.metadata,
      inserted_at: d.inserted_at
    }
  end
end
