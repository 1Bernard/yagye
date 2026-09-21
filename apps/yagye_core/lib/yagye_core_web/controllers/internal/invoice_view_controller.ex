defmodule YagyeCoreWeb.Controllers.Internal.InvoiceViewController do
  use YagyeCoreWeb, :controller

  alias YagyeCore.Invoices
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Repo

  @base_url Application.compile_env(:yagye_core, :checkout_base_url, "https://pay.yagye.com")

  # GET /internal/invoices/:public_id/view
  # No merchant auth — public_id is the capability. Draft invoices return 404.
  def show(conn, %{"public_id" => public_id}) do
    with {:ok, invoice} <- Invoices.get_invoice(public_id),
         :ok <- ensure_not_draft(invoice) do
      merchant = Repo.get(Merchant, invoice.merchant_id)
      logo_url = fetch_logo_url(invoice.payment_link_id)

      conn
      |> put_status(:ok)
      |> json(render_invoice(invoice, merchant, logo_url))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :draft} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp ensure_not_draft(%{state: "draft"}), do: {:error, :draft}
  defp ensure_not_draft(_), do: :ok

  defp fetch_logo_url(nil), do: nil

  defp fetch_logo_url(payment_link_id) do
    case Repo.get(PaymentLink, payment_link_id) do
      nil -> nil
      link -> (link.checkout_layout || %{})["logo_url"]
    end
  end

  defp render_invoice(invoice, merchant, logo_url) do
    customer_ref =
      case invoice.customer do
        %{merchant_customer_ref: ref} when is_binary(ref) -> ref
        _ -> nil
      end

    payment_link_slug =
      case invoice.payment_link do
        %{url_slug: slug} -> slug
        _ -> nil
      end

    %{
      number: invoice.number,
      state: invoice.state,
      currency: invoice.currency,
      issue_date: invoice.issue_date,
      due_date: invoice.due_date,
      subtotal_amount: invoice.subtotal_amount,
      tax_amount: invoice.tax_amount,
      discount_amount: invoice.discount_amount,
      total_amount: invoice.total_amount,
      amount_paid: invoice.amount_paid,
      amount_due: invoice.amount_due,
      notes: invoice.notes,
      terms: invoice.terms,
      customer_reference: customer_ref,
      merchant: %{
        name: merchant && merchant.trading_name,
        logo_url: logo_url
      },
      payment_link_slug: payment_link_slug,
      checkout_url: payment_link_slug && "#{@base_url}/#{payment_link_slug}",
      line_items:
        (invoice.line_items || [])
        |> Enum.map(fn item ->
          %{
            description: item.description,
            quantity: item.quantity,
            unit_amount: item.unit_amount,
            tax_rate_bps: item.tax_rate_bps,
            total_amount: item.total_amount,
            position: item.position
          }
        end)
        |> Enum.sort_by(& &1.position)
    }
  end
end
