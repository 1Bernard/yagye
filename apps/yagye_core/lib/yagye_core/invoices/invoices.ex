defmodule YagyeCore.Invoices do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Customers
  alias YagyeCore.Invoices.Schemas.{Invoice, InvoiceDelivery, InvoiceLineItem}
  alias YagyeCore.Merchants
  alias YagyeCore.PaymentLinks
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Pagination

  # ── Public API ───────────────────────────────────────────────────────────────

  def list_invoices(merchant_id, opts \\ []) do
    state = Keyword.get(opts, :state)
    base = from(i in Invoice, where: i.merchant_id == ^merchant_id, preload: [:customer])
    base = if state, do: where(base, [i], i.state == ^state), else: base
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  def get_invoice(public_id) do
    case Repo.get_by(Invoice, public_id: public_id) do
      nil ->
        {:error, :not_found}

      invoice ->
        {:ok, Repo.preload(invoice, [:line_items, :deliveries, :customer, :payment_link])}
    end
  end

  def create_invoice(merchant_id, attrs) do
    with {:ok, customer_id} <- resolve_customer_id(merchant_id, attrs),
         {:ok, mode} <- resolve_mode_for(merchant_id, attrs) do
      do_create_invoice(merchant_id, mode, customer_id, attrs)
    end
  end

  defp do_create_invoice(merchant_id, mode, customer_id, attrs) do
    line_item_attrs = Map.get(attrs, :line_items, [])
    invoice_attrs = Map.drop(attrs, [:line_items, :customer_reference, :merchant_customer_ref])

    {subtotal, tax, total} = compute_totals(line_item_attrs)

    base_attrs =
      invoice_attrs
      |> Map.put(:merchant_id, merchant_id)
      |> Map.put(:customer_id, customer_id)
      |> Map.put(:mode, mode)
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
          unit = Map.get(item, :unit_amount, 0)
          qty = item |> Map.get(:quantity, 1) |> to_float()
          bps = Map.get(item, :tax_rate_bps, 0)
          total = round(unit * qty + unit * qty * bps / 10_000)

          %InvoiceLineItem{}
          |> InvoiceLineItem.changeset(
            Map.merge(item, %{invoice_id: invoice.id, position: idx, total_amount: total})
          )
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

  def update_invoice(public_id, attrs) do
    with {:ok, invoice} <- get_invoice(public_id) do
      if invoice.state != "draft",
        do: {:error, :not_draft},
        else: run_update_transaction(invoice, attrs)
    end
  end

  defp run_update_transaction(invoice, attrs) do
    line_item_attrs = Map.get(attrs, :line_items, [])

    invoice_attrs = Map.drop(attrs, [:line_items, :customer_reference, :merchant_customer_ref])
    {subtotal, tax, total} = compute_totals(line_item_attrs)

    base_attrs =
      invoice_attrs
      |> Map.put(:subtotal_amount, subtotal)
      |> Map.put(:tax_amount, tax)
      |> Map.put(:total_amount, total)
      |> Map.put(:amount_due, total)

    result =
      Multi.new()
      |> Multi.update(:invoice, Invoice.changeset(invoice, base_attrs))
      |> Multi.delete_all(
        :old_items,
        from(li in InvoiceLineItem, where: li.invoice_id == ^invoice.id)
      )
      |> Multi.run(:line_items, fn repo, %{invoice: inv} ->
        insert_line_items(repo, inv, line_item_attrs)
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{invoice: inv}} -> get_invoice(inv.public_id)
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def issue_invoice(public_id, payment_config \\ %{}) do
    with {:ok, invoice} <- get_invoice(public_id) do
      allowed_methods =
        case Map.get(payment_config, :allowed_methods) do
          methods when is_list(methods) and methods != [] -> methods
          _ -> ["mobile_money"]
        end

      link_attrs = %{
        kind: "invoice",
        currency: invoice.currency,
        amount: invoice.total_amount,
        description: "Invoice #{invoice.number}",
        allowed_methods: allowed_methods,
        collect_email: Map.get(payment_config, :collect_email, false),
        collect_phone: Map.get(payment_config, :collect_phone, false),
        collect_name: Map.get(payment_config, :collect_name, false),
        reusable: false,
        active: true,
        checkout_layout: %{},
        metadata: %{}
      }

      Multi.new()
      |> Multi.run(:link, fn _repo, _ ->
        PaymentLinks.create_link(invoice.merchant_id, link_attrs)
      end)
      |> Multi.update(:invoice, fn %{link: link} ->
        Invoice.state_changeset(invoice, "open", %{
          payment_link_id: link.id,
          sent_at: DateTime.utc_now()
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{invoice: inv, link: link}} -> {:ok, %{inv | payment_link: link}}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  def apply_payment(%Invoice{} = invoice, payment_amount)
      when is_integer(payment_amount) and payment_amount > 0 do
    new_paid = invoice.amount_paid + payment_amount
    new_due = max(invoice.amount_due - payment_amount, 0)

    {new_state, paid_at} =
      if new_due == 0,
        do: {"paid", DateTime.utc_now()},
        else: {"partially_paid", nil}

    extra = %{amount_paid: new_paid, amount_due: new_due}
    extra = if paid_at, do: Map.put(extra, :paid_at, paid_at), else: extra

    invoice
    |> Invoice.apply_payment_changeset(new_state, extra)
    |> Repo.update()
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

  # Accept a pre-resolved customer_id (internal callers) or resolve from a reference string.
  defp resolve_customer_id(_merchant_id, %{customer_id: id}) when is_binary(id), do: {:ok, id}

  defp resolve_customer_id(merchant_id, attrs) do
    ref = Map.get(attrs, :customer_reference) || Map.get(attrs, :merchant_customer_ref)
    resolve_customer_by_ref(merchant_id, ref)
  end

  defp resolve_customer_by_ref(_merchant_id, nil), do: {:error, :customer_reference_required}

  defp resolve_customer_by_ref(merchant_id, ref) do
    case Customers.find_or_create(merchant_id, ref, %{}) do
      {:ok, customer} -> {:ok, customer.id}
      {:error, _} = err -> err
    end
  end

  # Use the caller-supplied mode when provided (allows override and changeset validation of bad values).
  # Fall back to resolving from merchant live-mode flag.
  defp resolve_mode_for(_merchant_id, %{mode: mode}) when is_binary(mode), do: {:ok, mode}

  defp resolve_mode_for(merchant_id, _attrs) do
    mode =
      cond do
        Merchants.live_mode_enabled?(merchant_id) -> "live"
        Merchants.sandbox_mode_enabled?(merchant_id) -> "sandbox"
        true -> "simulation"
      end

    {:ok, mode}
  end

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

  defp insert_line_items(repo, inv, line_item_attrs) do
    items =
      line_item_attrs
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        unit = Map.get(item, :unit_amount, 0)
        qty = item |> Map.get(:quantity, 1) |> to_float()
        bps = Map.get(item, :tax_rate_bps, 0)
        total_li = round(unit * qty + unit * qty * bps / 10_000)

        %InvoiceLineItem{}
        |> InvoiceLineItem.changeset(
          Map.merge(item, %{invoice_id: inv.id, position: idx, total_amount: total_li})
        )
        |> repo.insert()
      end)

    errors = Enum.filter(items, &match?({:error, _}, &1))
    if errors == [], do: {:ok, Enum.map(items, fn {:ok, i} -> i end)}, else: hd(errors)
  end
end
