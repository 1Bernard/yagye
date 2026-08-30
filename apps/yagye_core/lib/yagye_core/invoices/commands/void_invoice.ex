defmodule YagyeCore.Invoices.Commands.VoidInvoice do
  @moduledoc false
  @enforce_keys [:invoice_id, :voided_by]
  defstruct [:invoice_id, :voided_by]
end
