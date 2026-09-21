defmodule YagyeCheckoutWeb.Live.InvoiceLive do
  use Phoenix.LiveView, layout: {YagyeCheckoutWeb.Layouts, :checkout}

  alias YagyeCheckout.CoreClient

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case CoreClient.get_invoice_view(id) do
      {:ok, invoice} ->
        {:ok, assign(socket, page_state: :loaded, invoice: invoice)}

      {:error, :not_found} ->
        {:ok, assign(socket, page_state: :not_found, invoice: nil)}

      {:error, _} ->
        {:ok, assign(socket, page_state: :error, invoice: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.styles />
    <%= case @page_state do %>
      <% :loaded -> %>
        <.invoice_page invoice={@invoice} />
      <% :not_found -> %>
        <.error_page message="This invoice could not be found." />
      <% _ -> %>
        <.error_page message="Something went wrong. Please try again." />
    <% end %>
    """
  end

  # ── Components ───────────────────────────────────────────────────────────────

  defp invoice_page(assigns) do
    state = assigns.invoice["state"]
    due_date = parse_date(assigns.invoice["due_date"])
    overdue = state == "open" and due_date != nil and Date.compare(due_date, Date.utc_today()) == :lt
    payable = state in ["open", "partially_paid"] and not (state == "open" and overdue)
    paid = state == "paid"
    void = state == "void"

    assigns =
      assigns
      |> assign(overdue: overdue)
      |> assign(payable: payable)
      |> assign(paid: paid)
      |> assign(void: void)
      |> assign(status_label: status_label(state, overdue))
      |> assign(status_class: status_class(state, overdue))

    ~H"""
    <div class="inv-page">
      <div class="inv-card">
        <div class="inv-header">
          <div class="inv-merchant">
            <% logo = get_in(@invoice, ["merchant", "logo_url"]) %>
            <%= if logo && logo != "" do %>
              <img src={logo} alt="Logo" class="inv-logo" />
            <% else %>
              <div class="inv-logo-bubble">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
                  fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                </svg>
              </div>
            <% end %>
            <span class="inv-merchant-name">
              <%= get_in(@invoice, ["merchant", "name"]) || "Merchant" %>
            </span>
          </div>

          <div class="inv-meta-right">
            <div class="inv-number">Invoice #<%= @invoice["number"] %></div>
            <span class={"inv-status #{@status_class}"}><%= @status_label %></span>
          </div>
        </div>

        <div class="inv-divider" />

        <div class="inv-info-row">
          <div class="inv-info-block">
            <div class="inv-label">Bill to</div>
            <div class="inv-value inv-bill-to">
              <%= @invoice["customer_reference"] || "—" %>
            </div>
          </div>
          <div class="inv-info-block inv-info-right">
            <div class="inv-date-pair">
              <span class="inv-label">Issue date</span>
              <span class="inv-value"><%= format_date(@invoice["issue_date"]) %></span>
            </div>
            <div class="inv-date-pair">
              <span class={"inv-label #{if @overdue, do: "inv-label--danger"}"}> Due date</span>
              <span class={"inv-value #{if @overdue, do: "inv-value--danger"}"}><%= format_date(@invoice["due_date"]) %></span>
            </div>
          </div>
        </div>

        <div class="inv-items">
          <div class="inv-items-header">
            <span class="inv-col inv-col--desc">Description</span>
            <span class="inv-col inv-col--qty">Qty</span>
            <span class="inv-col inv-col--unit">Unit price</span>
            <span class="inv-col inv-col--total">Total</span>
          </div>
          <%= for item <- (@invoice["line_items"] || []) do %>
            <div class="inv-item-row">
              <span class="inv-col inv-col--desc">
                <%= item["description"] %>
                <%= if (item["tax_rate_bps"] || 0) > 0 do %>
                  <span class="inv-tax-badge">+<%= div(item["tax_rate_bps"], 100) %>% tax</span>
                <% end %>
              </span>
              <span class="inv-col inv-col--qty"><%= format_quantity(item["quantity"]) %></span>
              <span class="inv-col inv-col--unit"><%= format_amount(@invoice["currency"], item["unit_amount"]) %></span>
              <span class="inv-col inv-col--total"><%= format_amount(@invoice["currency"], item["total_amount"]) %></span>
            </div>
          <% end %>
        </div>

        <div class="inv-totals">
          <div class="inv-total-row">
            <span class="inv-total-label">Subtotal</span>
            <span class="inv-total-value"><%= format_amount(@invoice["currency"], @invoice["subtotal_amount"]) %></span>
          </div>
          <%= if (@invoice["tax_amount"] || 0) > 0 do %>
            <div class="inv-total-row">
              <span class="inv-total-label">Tax</span>
              <span class="inv-total-value"><%= format_amount(@invoice["currency"], @invoice["tax_amount"]) %></span>
            </div>
          <% end %>
          <%= if (@invoice["discount_amount"] || 0) > 0 do %>
            <div class="inv-total-row">
              <span class="inv-total-label">Discount</span>
              <span class="inv-total-value inv-discount">−<%= format_amount(@invoice["currency"], @invoice["discount_amount"]) %></span>
            </div>
          <% end %>
          <div class="inv-divider inv-divider--sm" />
          <div class="inv-total-row inv-total-row--grand">
            <span class="inv-total-label">Total</span>
            <span class="inv-total-value inv-grand-total"><%= format_amount(@invoice["currency"], @invoice["total_amount"]) %></span>
          </div>
          <%= if (@invoice["amount_paid"] || 0) > 0 do %>
            <div class="inv-total-row">
              <span class="inv-total-label">Amount paid</span>
              <span class="inv-total-value inv-paid-credit">−<%= format_amount(@invoice["currency"], @invoice["amount_paid"]) %></span>
            </div>
            <div class="inv-total-row inv-total-row--due">
              <span class="inv-total-label">Amount due</span>
              <span class="inv-total-value inv-amount-due"><%= format_amount(@invoice["currency"], @invoice["amount_due"]) %></span>
            </div>
          <% end %>
        </div>

        <%= if @invoice["notes"] do %>
          <div class="inv-notes">
            <div class="inv-notes-label">Notes</div>
            <p class="inv-notes-text"><%= @invoice["notes"] %></p>
          </div>
        <% end %>
        <%= if @invoice["terms"] do %>
          <div class="inv-notes">
            <div class="inv-notes-label">Terms</div>
            <p class="inv-notes-text"><%= @invoice["terms"] %></p>
          </div>
        <% end %>

        <div class="inv-cta">
          <%= cond do %>
            <% @void -> %>
              <div class="inv-banner inv-banner--void">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none"
                  stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                  <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
                </svg>
                This invoice has been voided
              </div>
            <% @paid -> %>
              <div class="inv-banner inv-banner--paid">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none"
                  stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="20 6 9 17 4 12"/>
                </svg>
                Paid in full · Thank you
              </div>
            <% @payable -> %>
              <a href={@invoice["checkout_url"]} class="inv-pay-btn">
                Pay <%= format_amount(@invoice["currency"], @invoice["amount_due"]) %>
                <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none"
                  stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                  <line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/>
                </svg>
              </a>
            <% true -> %>
              <div class="inv-banner inv-banner--overdue">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none"
                  stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
                  <line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
                </svg>
                This invoice is overdue — please contact the merchant
              </div>
          <% end %>
        </div>

        <div class="inv-footer">
          <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none"
            stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
          </svg>
          Secured by <strong>Yagye</strong>
        </div>
      </div>
    </div>
    """
  end

  defp error_page(assigns) do
    ~H"""
    <div class="inv-page">
      <div class="inv-card inv-card--error">
        <div class="inv-error-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"
            fill="none" stroke="#9ca3af" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/>
            <line x1="12" y1="16" x2="12.01" y2="16"/>
          </svg>
        </div>
        <p class="inv-error-title">Invoice not found</p>
        <p class="inv-error-body"><%= @message %></p>
        <div class="inv-footer" style="margin-top:2rem">
          <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none"
            stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
          </svg>
          Secured by <strong>Yagye</strong>
        </div>
      </div>
    </div>
    """
  end

  defp styles(assigns) do
    ~H"""
    <style>
      *, *::before, *::after { box-sizing: border-box; }

      .inv-page {
        min-height: 100svh;
        background: #f1f5f9;
        display: flex;
        align-items: flex-start;
        justify-content: center;
        padding: 2rem 1rem 4rem;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter", sans-serif;
      }

      .inv-card {
        background: #ffffff;
        border-radius: 16px;
        border: 1px solid #e2e8f0;
        box-shadow: 0 4px 24px rgba(0,0,0,0.06), 0 1px 4px rgba(0,0,0,0.04);
        width: 100%;
        max-width: 680px;
        padding: 2rem;
      }

      .inv-card--error {
        max-width: 400px;
        text-align: center;
        padding: 3rem 2rem;
        margin-top: 4rem;
      }

      .inv-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        margin-bottom: 1.5rem;
        gap: 1rem;
      }

      .inv-merchant {
        display: flex;
        align-items: center;
        gap: 0.625rem;
      }

      .inv-logo {
        width: 36px;
        height: 36px;
        border-radius: 8px;
        object-fit: cover;
        border: 1px solid #f1f5f9;
        flex-shrink: 0;
      }

      .inv-logo-bubble {
        width: 36px;
        height: 36px;
        border-radius: 8px;
        background: #3D47F5;
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        flex-shrink: 0;
      }

      .inv-merchant-name {
        font-size: 0.9375rem;
        font-weight: 700;
        color: #111827;
        letter-spacing: -0.01em;
      }

      .inv-meta-right {
        text-align: right;
        flex-shrink: 0;
      }

      .inv-number {
        font-size: 1rem;
        font-weight: 700;
        color: #111827;
        letter-spacing: -0.01em;
        margin-bottom: 0.375rem;
      }

      .inv-status {
        display: inline-block;
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        padding: 0.2rem 0.625rem;
        border-radius: 999px;
      }

      .inv-status--open    { background: #eff6ff; color: #2563eb; }
      .inv-status--partial { background: #fffbeb; color: #d97706; }
      .inv-status--paid    { background: #f0fdf4; color: #16a34a; }
      .inv-status--overdue { background: #fef2f2; color: #dc2626; }
      .inv-status--void    { background: #f9fafb; color: #6b7280; border: 1px solid #e5e7eb; }

      .inv-divider { height: 1px; background: #f1f5f9; margin: 1.25rem 0; }
      .inv-divider--sm { margin: 0.75rem 0; }

      .inv-info-row {
        display: flex;
        justify-content: space-between;
        gap: 1rem;
        margin-bottom: 1.75rem;
      }

      .inv-info-right { text-align: right; }

      .inv-label {
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: #9ca3af;
        margin-bottom: 0.25rem;
      }

      .inv-label--danger { color: #dc2626; }

      .inv-value {
        font-size: 0.9375rem;
        font-weight: 600;
        color: #111827;
      }

      .inv-value--danger { color: #dc2626; }
      .inv-bill-to { max-width: 200px; }

      .inv-date-pair {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        justify-content: flex-end;
        margin-bottom: 0.35rem;
      }

      .inv-date-pair .inv-label { margin-bottom: 0; }

      .inv-items-header {
        display: flex;
        gap: 0.5rem;
        padding: 0.5rem 0;
        border-bottom: 1px solid #f1f5f9;
        margin-bottom: 0.25rem;
      }

      .inv-item-row {
        display: flex;
        gap: 0.5rem;
        padding: 0.625rem 0;
        border-bottom: 1px solid #f8fafc;
        align-items: flex-start;
      }

      .inv-col { font-size: 0.8125rem; }

      .inv-items-header .inv-col {
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        color: #9ca3af;
      }

      .inv-col--desc  { flex: 1; color: #374151; font-weight: 500; }
      .inv-col--qty   { width: 48px; text-align: center; color: #6b7280; }
      .inv-col--unit  { width: 100px; text-align: right; color: #6b7280; }
      .inv-col--total { width: 100px; text-align: right; color: #111827; font-weight: 600; font-variant-numeric: tabular-nums; }

      .inv-items-header .inv-col--desc,
      .inv-items-header .inv-col--qty,
      .inv-items-header .inv-col--unit,
      .inv-items-header .inv-col--total { color: #9ca3af; }

      .inv-tax-badge {
        display: inline-block;
        font-size: 0.625rem;
        font-weight: 600;
        background: #f0fdf4;
        color: #16a34a;
        padding: 0.1rem 0.4rem;
        border-radius: 4px;
        margin-left: 0.375rem;
        vertical-align: middle;
      }

      .inv-totals {
        margin-top: 1rem;
        padding-top: 0.75rem;
        max-width: 280px;
        margin-left: auto;
      }

      .inv-total-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0.3rem 0;
        gap: 1.5rem;
      }

      .inv-total-row--grand { padding: 0.5rem 0; }
      .inv-total-row--due   { padding-top: 0.5rem; border-top: 1px solid #f1f5f9; }

      .inv-total-label { font-size: 0.8125rem; color: #6b7280; font-weight: 500; }

      .inv-total-value {
        font-size: 0.8125rem;
        color: #374151;
        font-weight: 500;
        font-variant-numeric: tabular-nums;
      }

      .inv-grand-total { font-size: 1.0625rem; font-weight: 800; color: #111827; letter-spacing: -0.01em; }
      .inv-discount    { color: #16a34a; }
      .inv-paid-credit { color: #16a34a; }
      .inv-amount-due  { color: #111827; font-weight: 700; }

      .inv-notes {
        margin-top: 1.5rem;
        padding: 1rem;
        background: #f8fafc;
        border-radius: 10px;
        border: 1px solid #f1f5f9;
      }

      .inv-notes-label {
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        color: #9ca3af;
        margin-bottom: 0.4rem;
      }

      .inv-notes-text {
        font-size: 0.8125rem;
        color: #4b5563;
        line-height: 1.6;
        margin: 0;
        white-space: pre-wrap;
      }

      .inv-cta { margin-top: 1.75rem; }

      .inv-pay-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 0.5rem;
        width: 100%;
        padding: 0.875rem;
        background: #3D47F5;
        color: #fff;
        font-size: 0.9375rem;
        font-weight: 700;
        border-radius: 12px;
        text-decoration: none;
        transition: background 0.15s;
        letter-spacing: -0.01em;
      }

      .inv-pay-btn:hover { background: #2e38d4; }

      .inv-banner {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.75rem 1rem;
        border-radius: 10px;
        font-size: 0.875rem;
        font-weight: 600;
      }

      .inv-banner--paid    { background: #f0fdf4; color: #16a34a; }
      .inv-banner--void    { background: #f9fafb; color: #6b7280; border: 1px solid #e5e7eb; }
      .inv-banner--overdue { background: #fef2f2; color: #dc2626; }

      .inv-footer {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 0.3rem;
        margin-top: 1.5rem;
        padding-top: 1.25rem;
        border-top: 1px solid #f1f5f9;
        font-size: 0.75rem;
        color: #9ca3af;
      }

      .inv-footer strong { color: #3D47F5; }

      .inv-error-icon {
        width: 56px;
        height: 56px;
        background: #f3f4f6;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        margin: 0 auto 1.25rem;
      }

      .inv-error-title { font-size: 1.125rem; font-weight: 700; color: #111827; margin: 0 0 0.5rem; }
      .inv-error-body  { font-size: 0.875rem; color: #6b7280; margin: 0; line-height: 1.6; }

      @media (max-width: 600px) {
        .inv-page { padding: 1rem 0.75rem 3rem; }
        .inv-card { padding: 1.25rem; border-radius: 12px; }
        .inv-col--unit  { width: 80px; }
        .inv-col--total { width: 80px; }
        .inv-totals { max-width: 100%; }
      }
    </style>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────────

  defp status_label("open", true),        do: "Overdue"
  defp status_label("open", false),       do: "Open"
  defp status_label("partially_paid", _), do: "Partial"
  defp status_label("paid", _),           do: "Paid"
  defp status_label("void", _),           do: "Void"
  defp status_label(s, _),               do: String.capitalize(s)

  defp status_class("open", true),        do: "inv-status--overdue"
  defp status_class("open", false),       do: "inv-status--open"
  defp status_class("partially_paid", _), do: "inv-status--partial"
  defp status_class("paid", _),           do: "inv-status--paid"
  defp status_class("void", _),           do: "inv-status--void"
  defp status_class(_, _),               do: "inv-status--open"

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(%Date{} = d), do: d

  defp format_date(nil), do: "—"

  defp format_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> format_date(date)
      _ -> date_str
    end
  end

  defp format_date(%Date{} = date) do
    months = ~w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
    month = Enum.at(months, date.month - 1)
    "#{date.day} #{month} #{date.year}"
  end

  defp format_quantity(nil), do: "1"

  defp format_quantity(qty) when is_float(qty) do
    if qty == Float.floor(qty),
      do: "#{round(qty)}",
      else: :erlang.float_to_binary(qty, decimals: 2)
  end

  defp format_quantity(qty), do: "#{qty}"

  defp format_amount(currency, nil), do: "#{currency_symbol(currency)}0.00"

  defp format_amount(currency, minor_units) do
    sym = currency_symbol(currency)
    major = div(minor_units, 100)
    cents = rem(minor_units, 100)
    "#{sym}#{major}.#{String.pad_leading("#{cents}", 2, "0")}"
  end

  defp currency_symbol("GHS"), do: "GH₵"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("GBP"), do: "£"
  defp currency_symbol("NGN"), do: "₦"
  defp currency_symbol(code), do: "#{code} "
end
