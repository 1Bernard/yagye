defmodule YagyeCore.Invoices.Events.InvoiceVoided do
  @moduledoc false
  defstruct [:invoice_id, :merchant_id, :voided_by, :occurred_at]
end
