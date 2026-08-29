defmodule YagyeCore.Payments.Commands.DispatchPayment do
  @moduledoc false
  @enforce_keys [:payment_id]
  defstruct [:payment_id]
end
