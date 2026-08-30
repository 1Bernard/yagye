defmodule YagyeCore.Routing.Commands.EvaluateRouting do
  @moduledoc false
  @enforce_keys [:merchant_id, :mode, :method, :amount, :currency]
  defstruct [:merchant_id, :mode, :method, :amount, :currency, metadata: %{}]
end
