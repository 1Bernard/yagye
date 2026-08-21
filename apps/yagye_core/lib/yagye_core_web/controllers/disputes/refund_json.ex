defmodule YagyeCoreWeb.Controllers.Disputes.RefundJSON do
  @moduledoc false

  alias YagyeCore.Disputes.Schemas.Refund

  def data(%Refund{} = r) do
    %{
      id: r.public_id,
      object: "refund",
      payment_id: r.payment_id,
      dispute_id: dispute_public_id(r),
      amount: r.amount,
      currency: r.currency,
      reason: r.reason,
      state: r.state,
      failure_reason: r.failure_reason,
      metadata: r.metadata,
      inserted_at: r.inserted_at
    }
  end

  defp dispute_public_id(%Refund{dispute: %{public_id: id}}), do: id
  defp dispute_public_id(_), do: nil
end
