defmodule YagyeCore.Payments.Events.PaymentSucceeded do
  @moduledoc false
  defstruct [
    :payment_id,
    :merchant_id,
    :amount,
    :currency,
    :provider_code,
    :net_amount,
    :occurred_at
  ]
end
