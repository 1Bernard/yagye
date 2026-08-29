defmodule YagyeCore.Disputes.Commands.CreateDispute do
  @moduledoc false
  @enforce_keys [:payment_id]
  defstruct [:payment_id, :network, :reason, :amount, :currency, metadata: %{}]
end
