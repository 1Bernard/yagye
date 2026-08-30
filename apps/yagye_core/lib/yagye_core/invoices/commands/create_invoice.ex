defmodule YagyeCore.Invoices.Commands.CreateInvoice do
  @moduledoc false
  @enforce_keys [:merchant_id, :customer_id, :mode, :currency, :issue_date, :due_date]
  defstruct [
    :merchant_id,
    :customer_id,
    :mode,
    :currency,
    :issue_date,
    :due_date,
    :notes,
    :terms,
    line_items: []
  ]
end
