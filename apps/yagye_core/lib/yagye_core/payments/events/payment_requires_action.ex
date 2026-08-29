defmodule YagyeCore.Payments.Events.PaymentRequiresAction do
  @moduledoc false
  defstruct [:payment_id, :merchant_id, :method, :amount, :currency, :occurred_at]
end
