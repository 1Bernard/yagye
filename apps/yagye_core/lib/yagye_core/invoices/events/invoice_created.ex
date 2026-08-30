defmodule YagyeCore.Invoices.Events.InvoiceCreated do
  @moduledoc false
  defstruct [
    :invoice_id,
    :merchant_id,
    :customer_id,
    :mode,
    :total_amount,
    :currency,
    :occurred_at
  ]
end
