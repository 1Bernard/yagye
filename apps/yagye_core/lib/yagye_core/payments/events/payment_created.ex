defmodule YagyeCore.Payments.Events.PaymentCreated do
  @moduledoc false
  defstruct [
    :payment_id,
    :merchant_id,
    :amount,
    :currency,
    :method,
    :mode,
    :merchant_reference,
    :customer_reference,
    :occurred_at
  ]
end
