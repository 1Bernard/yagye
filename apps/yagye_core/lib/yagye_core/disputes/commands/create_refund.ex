defmodule YagyeCore.Disputes.Commands.CreateRefund do
  @moduledoc false
  @enforce_keys [:payment_id, :amount]
  defstruct [:payment_id, :amount, :reason, metadata: %{}]
end
