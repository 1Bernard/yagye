defmodule YagyeCore.Disputes.Events.DisputeOpened do
  @moduledoc false
  defstruct [
    :dispute_id,
    :payment_id,
    :merchant_id,
    :network,
    :reason,
    :amount,
    :currency,
    :occurred_at
  ]
end
