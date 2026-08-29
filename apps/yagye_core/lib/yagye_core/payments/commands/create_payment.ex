defmodule YagyeCore.Payments.Commands.CreatePayment do
  @moduledoc false
  @enforce_keys [:merchant_id, :amount, :currency, :method]
  defstruct [
    :merchant_id,
    :amount,
    :currency,
    :method,
    :customer_reference,
    :merchant_reference,
    :description,
    metadata: %{}
  ]
end
