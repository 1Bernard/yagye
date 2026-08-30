defmodule YagyeCoreWeb.Controllers.Invoices.InvoiceJSON do
  @moduledoc false

  alias YagyeCore.Invoices.Schemas.Invoice

  def data(%Invoice{} = invoice) do
    %{
      id: invoice.public_id,
      object: "invoice",
      mode: invoice.mode,
      number: invoice.number,
      state: invoice.state,
      currency: invoice.currency,
      subtotal_amount: invoice.subtotal_amount,
      tax_amount: invoice.tax_amount,
      discount_amount: invoice.discount_amount,
      total_amount: invoice.total_amount,
      amount_paid: invoice.amount_paid,
      amount_due: invoice.amount_due,
      issue_date: invoice.issue_date,
      due_date: invoice.due_date,
      notes: invoice.notes,
      terms: invoice.terms,
      sent_at: invoice.sent_at,
      paid_at: invoice.paid_at,
      voided_at: invoice.voided_at,
      inserted_at: invoice.inserted_at
    }
  end

  def list(invoices), do: %{object: "list", data: Enum.map(invoices, &data/1)}
end
