defmodule YagyeCore.Payments.Events.PaymentIndeterminate do
  @moduledoc false
  defstruct [:payment_id, :merchant_id, :response_code, :occurred_at]
end
