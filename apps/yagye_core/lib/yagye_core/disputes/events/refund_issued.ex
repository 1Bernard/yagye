defmodule YagyeCore.Disputes.Events.RefundIssued do
  @moduledoc false
  defstruct [
    :refund_id,
    :payment_id,
    :merchant_id,
    :amount,
    :currency,
    :dispute_retracted,
    :occurred_at
  ]
end
