defmodule YagyeCore.Invoices do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Invoices.Schemas.{Invoice, InvoiceDelivery, InvoiceLineItem}
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def list_invoices(merchant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    state = Keyword.get(opts, :state)

    base =
      from(i in Invoice,
        where: i.merchant_id == ^merchant_id,
        order_by: [desc: i.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query = if state, do: where(base, [i], i.state == ^state), else: base
    {:ok, Repo.all(query)}
  end

  def get_invoice(public_id) do
    case Repo.get_by(Invoice, public_id: public_id) do
      nil -> {:error, :not_found}
      invoice -> {:ok, Repo.preload(invoice, [:line_items, :deliveries])}
    end
  end

  def create_invoice(merchant_id, attrs) do
    line_item_attrs = Map.get(attrs, :line_items, [])
    invoice_attrs = Map.drop(attrs, [:line_items])

    {subtotal, tax, total} = compute_totals(line_item_attrs)

    base_attrs =
      invoice_attrs
      |> Map.put(:merchant_id, merchant_id)
      |> Map.put(:subtotal_amount, subtotal)
      |> Map.put(:tax_amount, tax)
      |> Map.put(:discount_amount, Map.get(invoice_attrs, :discount_amount, 0))
      |> Map.put(:total_amount, total)
      |> Map.put(:amount_due, total)

    Multi.new()
    |> Multi.insert(:invoice, Invoice.changeset(%Invoice{}, base_attrs))
    |> Multi.run(:line_items, fn repo, %{invoice: invoice} ->
      items =
        line_item_attrs
        |> Enum.with_index()
        |> Enum.map(fn {item, idx} ->
          %InvoiceLineItem{}
          |> InvoiceLineItem.changeset(Map.merge(item, %{invoice_id: invoice.id, position: idx}))
          |> repo.insert()
        end)

      errors = Enum.filter(items, &match?({:error, _}, &1))
      if errors == [], do: {:ok, Enum.map(items, fn {:ok, i} -> i end)}, else: hd(errors)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{invoice: invoice}} -> {:ok, invoice}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def issue_invoice(public_id) do
    with {:ok, invoice} <- get_invoice(public_id) do
      invoice
      |> Invoice.state_changeset("open", %{})
      |> Repo.update()
    end
  end

  def void_invoice(public_id) do
    with {:ok, invoice} <- get_invoice(public_id) do
      invoice
      |> Invoice.state_changeset("void", %{voided_at: DateTime.utc_now()})
      |> Repo.update()
    end
  end

  def record_delivery(invoice_id, attrs) do
    %InvoiceDelivery{}
    |> InvoiceDelivery.changeset(Map.put(attrs, :invoice_id, invoice_id))
    |> Repo.insert()
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp compute_totals(line_items) do
    subtotal =
      Enum.reduce(line_items, 0, fn item, acc ->
        unit = Map.get(item, :unit_amount, 0)
        qty = to_float(Map.get(item, :quantity, 1))
        acc + unit * qty
      end)

    tax =
      Enum.reduce(line_items, 0, fn item, acc ->
        unit = Map.get(item, :unit_amount, 0)
        qty = to_float(Map.get(item, :quantity, 1))
        bps = Map.get(item, :tax_rate_bps, 0)
        acc + round(unit * qty * bps / 10_000)
      end)

    {round(subtotal), tax, round(subtotal) + tax}
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n), do: n * 1.0
end
