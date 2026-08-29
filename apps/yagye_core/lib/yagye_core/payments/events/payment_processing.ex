defmodule YagyeCore.Payments.Events.PaymentProcessing do
  @moduledoc false
  defstruct [:payment_id, :merchant_id, :occurred_at]
end
