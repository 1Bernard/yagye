defmodule YagyeCore.Payments.Events.PaymentAuthorised do
  @moduledoc false
  defstruct [:payment_id, :merchant_id, :provider_reference, :occurred_at]
end
