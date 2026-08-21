defmodule YagyeCore.Disputes.Events.DisputeResolved do
  @moduledoc false
  defstruct [:dispute_id, :payment_id, :merchant_id, :outcome, :occurred_at]
end
