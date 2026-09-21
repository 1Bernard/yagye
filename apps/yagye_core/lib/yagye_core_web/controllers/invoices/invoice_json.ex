defmodule YagyeCoreWeb.Controllers.Invoices.InvoiceJSON do
  @moduledoc false

  @base_url Application.compile_env(:yagye_core, :checkout_base_url, "https://pay.yagye.com")

  alias YagyeCore.Invoices.Schemas.Invoice

  def data(%Invoice{} = invoice) do
    customer_ref =
      case invoice.customer do
        %{merchant_customer_ref: ref} -> ref
        _ -> nil
      end

    line_items =
      case invoice.line_items do
        items when is_list(items) -> Enum.map(items, &line_item/1)
        _ -> []
      end

    %{
      id: invoice.public_id,
      object: "invoice",
      mode: invoice.mode,
      number: invoice.number,
      state: invoice.state,
      currency: invoice.currency,
      customer_reference: customer_ref,
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
      payment_link_id: invoice.payment_link_id,
      payment_link_checkout_url:
        case invoice.payment_link do
          %{url_slug: slug} -> "#{@base_url}/#{slug}"
          _ -> nil
        end,
      invoice_view_url: "#{@base_url}/inv/#{invoice.public_id}",
      line_items: line_items,
      sent_at: invoice.sent_at,
      paid_at: invoice.paid_at,
      voided_at: invoice.voided_at,
      inserted_at: invoice.inserted_at
    }
  end

  defp line_item(item) do
    %{
      description: item.description,
      quantity: item.quantity,
      unit_amount: item.unit_amount,
      tax_rate_bps: item.tax_rate_bps,
      total_amount: item.total_amount
    }
  end

  def list(%{data: invoices, has_more: has_more}) do
    %{object: "list", data: Enum.map(invoices, &data/1), has_more: has_more}
  end
end
