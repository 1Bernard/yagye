defmodule YagyeCore.Payments.Events.PaymentFailed do
  @moduledoc false
  defstruct [
    :payment_id,
    :merchant_id,
    :error_class,
    :response_code,
    :response_message,
    :occurred_at
  ]
end
