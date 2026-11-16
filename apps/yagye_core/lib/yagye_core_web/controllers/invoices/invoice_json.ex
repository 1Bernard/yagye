defmodule YagyeCoreWeb.Controllers.Invoices.InvoiceJSON do
  @moduledoc false

  alias YagyeCore.Checkout.Schemas.MerchantCheckoutConfig
  alias YagyeCore.Invoices.Schemas.Invoice
  alias YagyeCore.Repo

  def data(%Invoice{} = invoice) do
    logo_url =
      case Repo.get(MerchantCheckoutConfig, invoice.merchant_id) do
        %{logo_url: url} -> url
        _ -> nil
      end

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
          %{url_slug: slug} -> "#{checkout_base_url()}/#{slug}"
          _ -> nil
        end,
      payment_link: payment_link_send_config(invoice.payment_link),
      invoice_view_url: "#{checkout_base_url()}/inv/#{invoice.public_id}",
      pdf_s3_key: invoice.pdf_s3_key,
      checkout_layout: %{logo_url: logo_url},
      line_items: line_items,
      sent_at: invoice.sent_at,
      paid_at: invoice.paid_at,
      voided_at: invoice.voided_at,
      inserted_at: invoice.inserted_at
    }
  end

  defp payment_link_send_config(%Ecto.Association.NotLoaded{}), do: nil

  defp payment_link_send_config(%{} = link) do
    %{
      allowed_methods: link.allowed_methods,
      collect_email: link.collect_email,
      collect_phone: link.collect_phone,
      collect_name: link.collect_name
    }
  end

  defp payment_link_send_config(_), do: nil

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

  defp checkout_base_url,
    do: Application.get_env(:yagye_core, :checkout_base_url, "https://pay.yagye.com")
end
