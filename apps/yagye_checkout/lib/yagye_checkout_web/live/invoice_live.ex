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

        <%!-- ── Header: "Invoice" left · merchant right ── --%>
        <div class="inv-header">
          <div>
            <div class="inv-title">Invoice</div>
            <div class="inv-number"><%= @invoice["number"] %></div>
            <span class={"inv-badge inv-badge--#{@status_class}"}><%= @status_label %></span>
          </div>
          <div class="inv-merchant">
            <% merchant_name = get_in(@invoice, ["merchant", "name"]) || "Merchant" %>
            <% logo = get_in(@invoice, ["merchant", "logo_url"]) %>
            <span class="inv-merchant-name"><%= merchant_name %></span>
            <%= if logo && logo != "" do %>
              <img src={logo} alt="Logo" class="inv-logo" />
            <% else %>
              <div class="inv-logo-bubble">
                <%= String.upcase(String.slice(merchant_name, 0, 2)) %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- ── Billing strip ── --%>
        <div class="inv-strip-divider" />
        <div class="inv-billing">
          <div>
            <div class="inv-bl">Bill to</div>
            <div class="inv-bv"><%= @invoice["customer_reference"] || "—" %></div>
          </div>
          <div class="inv-dates">
            <div class="inv-date-col">
              <div class="inv-bl">Issued Date</div>
              <div class="inv-bv"><%= format_date(@invoice["issue_date"]) %></div>
            </div>
            <div class="inv-date-col">
              <div class={"inv-bl #{if @overdue, do: "inv-bl--danger"}"}>Due Date</div>
              <div class={"inv-bv #{if @overdue, do: "inv-bv--danger"}"}><%= format_date(@invoice["due_date"]) %></div>
            </div>
          </div>
        </div>
        <div class="inv-strip-divider" />

        <%!-- ── Line items ── --%>
        <div class="inv-table-wrap">
          <table class="inv-table">
            <thead>
              <tr class="inv-thead-row">
                <th class="inv-th inv-th--desc">Description</th>
                <th class="inv-th inv-th--num">Qty</th>
                <th class="inv-th inv-th--num">Unit price</th>
                <th class="inv-th inv-th--num">Tax</th>
                <th class="inv-th inv-th--amt">Amount</th>
              </tr>
            </thead>
            <tbody>
              <%= for item <- (@invoice["line_items"] || []) do %>
                <% bps = item["tax_rate_bps"] || 0 %>
                <tr class="inv-tr">
                  <td class="inv-td inv-td--desc"><%= item["description"] %></td>
                  <td class="inv-td inv-td--num"><%= format_quantity(item["quantity"]) %></td>
                  <td class="inv-td inv-td--num"><%= format_amount(@invoice["currency"], item["unit_amount"]) %></td>
                  <td class="inv-td inv-td--num"><%= if bps > 0, do: "#{div(bps, 100)}%", else: "—" %></td>
                  <td class="inv-td inv-td--amt"><%= format_amount(@invoice["currency"], item["total_amount"]) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <%!-- ── Totals ── --%>
        <div class="inv-totals-sep" />
        <div class="inv-totals">
          <div class="inv-totals-inner">
            <%= if (@invoice["subtotal_amount"] || 0) != (@invoice["total_amount"] || 0) or
                   (@invoice["tax_amount"] || 0) > 0 or (@invoice["discount_amount"] || 0) > 0 do %>
              <div class="inv-tr-row">
                <span class="inv-tl">Subtotal</span>
                <span class="inv-tv"><%= format_amount(@invoice["currency"], @invoice["subtotal_amount"]) %></span>
              </div>
            <% end %>
            <%= if (@invoice["tax_amount"] || 0) > 0 do %>
              <div class="inv-tr-row">
                <span class="inv-tl">Tax</span>
                <span class="inv-tv"><%= format_amount(@invoice["currency"], @invoice["tax_amount"]) %></span>
              </div>
            <% end %>
            <%= if (@invoice["discount_amount"] || 0) > 0 do %>
              <div class="inv-tr-row">
                <span class="inv-tl">Discount</span>
                <span class="inv-tv inv-tv--green">−<%= format_amount(@invoice["currency"], @invoice["discount_amount"]) %></span>
              </div>
            <% end %>
            <%= if (@invoice["amount_paid"] || 0) > 0 do %>
              <div class="inv-tr-row">
                <span class="inv-tl">Paid</span>
                <span class="inv-tv inv-tv--green">−<%= format_amount(@invoice["currency"], @invoice["amount_paid"]) %></span>
              </div>
            <% end %>
            <div class="inv-totals-line" />
            <div class="inv-tr-row inv-tr-row--total">
              <span class="inv-tl inv-tl--total">Total Amount</span>
              <span class="inv-tv inv-tv--total"><%= format_amount(@invoice["currency"], @invoice["total_amount"]) %></span>
            </div>
            <div class="inv-tr-row">
              <span class="inv-tl">Amount due</span>
              <span class="inv-tv inv-tv--due"><%= format_amount(@invoice["currency"], @invoice["amount_due"]) %></span>
            </div>
          </div>
        </div>

        <%!-- ── Notes / Terms ── --%>
        <%= if @invoice["notes"] || @invoice["terms"] do %>
          <div class="inv-notes-wrap">
            <%= if @invoice["notes"] do %>
              <div class="inv-notes-box">
                <p class="inv-notes-text"><%= @invoice["notes"] %></p>
              </div>
            <% end %>
            <%= if @invoice["terms"] do %>
              <div class="inv-notes-box">
                <div class="inv-bl" style="margin-bottom:6px">Terms &amp; conditions</div>
                <p class="inv-notes-text"><%= @invoice["terms"] %></p>
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- ── CTA ── --%>
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

        <%!-- ── Footer ── --%>
        <div class="inv-footer">
          <div>
            <div class="inv-footer-label">Payment method</div>
            <div class="inv-footer-sub">Payment powered by Yagye</div>
          </div>
          <div class="inv-footer-date"><%= format_date(Date.utc_today() |> Date.to_iso8601()) %></div>
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
      *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

      .inv-page {
        min-height: 100svh;
        background: #f1f5f9;
        display: flex;
        align-items: flex-start;
        justify-content: center;
        padding: 2rem 1rem 4rem;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter", sans-serif;
      }

      /* ── Card ── */
      .inv-card {
        background: #fff;
        border-radius: 16px;
        border: 1px solid #e2e8f0;
        box-shadow: 0 8px 40px rgba(0,0,0,0.10), 0 2px 12px rgba(0,0,0,0.06);
        width: 100%;
        max-width: 680px;
        overflow: hidden;
      }

      .inv-card--error {
        max-width: 400px;
        text-align: center;
        padding: 3rem 2rem;
        margin-top: 4rem;
        overflow: visible;
      }

      /* ── Header ── */
      .inv-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        padding: 2.25rem 2.5rem 1.5rem;
        gap: 1.5rem;
      }

      .inv-title {
        font-size: 2.125rem;
        font-weight: 900;
        color: #111827;
        letter-spacing: -0.03em;
        line-height: 1;
        margin-bottom: 6px;
      }

      .inv-number {
        font-size: 0.8125rem;
        color: #9ca3af;
        font-family: ui-monospace, "SF Mono", monospace;
        margin-bottom: 8px;
      }

      /* ── Status badge ── */
      .inv-badge {
        display: inline-block;
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        padding: 0.2rem 0.6rem;
        border-radius: 999px;
      }

      .inv-badge--open    { background: #eff6ff; color: #2563eb; }
      .inv-badge--partial { background: #fffbeb; color: #d97706; }
      .inv-badge--paid    { background: #f0fdf4; color: #16a34a; }
      .inv-badge--overdue { background: #fef2f2; color: #dc2626; }
      .inv-badge--void    { background: #f9fafb; color: #6b7280; border: 1px solid #e5e7eb; }

      /* ── Merchant (top right) ── */
      .inv-merchant {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        flex-shrink: 0;
        margin-top: 4px;
      }

      .inv-merchant-name {
        font-size: 0.9375rem;
        font-weight: 700;
        color: #111827;
        text-align: right;
        line-height: 1.3;
      }

      .inv-logo {
        width: 40px;
        height: 40px;
        border-radius: 9px;
        object-fit: cover;
        flex-shrink: 0;
      }

      .inv-logo-bubble {
        width: 40px;
        height: 40px;
        border-radius: 9px;
        background: #3D47F5;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #fff;
        font-size: 0.6875rem;
        font-weight: 800;
        letter-spacing: -0.01em;
        flex-shrink: 0;
      }

      /* ── Billing strip ── */
      .inv-strip-divider {
        height: 1px;
        background: #f1f5f9;
        margin: 0 2.5rem;
      }

      .inv-billing {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        padding: 1.25rem 2.5rem;
        gap: 1rem;
      }

      .inv-dates {
        display: flex;
        align-items: flex-start;
        gap: 1.75rem;
      }

      .inv-date-col { text-align: right; }

      /* Billing labels */
      .inv-bl {
        font-size: 0.59375rem;
        font-weight: 600;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: #9ca3af;
        margin-bottom: 5px;
      }

      .inv-bl--danger { color: #dc2626; }

      /* Billing values */
      .inv-bv {
        font-size: 0.84375rem;
        font-weight: 600;
        color: #111827;
      }

      .inv-bv--danger { color: #dc2626; }

      /* ── Line items table ── */
      .inv-table-wrap {
        padding: 0 1.5rem;
        overflow-x: auto;
      }

      .inv-table {
        width: 100%;
        border-collapse: collapse;
      }

      .inv-thead-row {
        background: #f9fafb;
        border-bottom: 1px solid #f1f5f9;
      }

      .inv-th {
        font-size: 0.65625rem;
        font-weight: 700;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: #9ca3af;
        padding: 0.75rem 0.75rem;
        white-space: nowrap;
      }

      .inv-th--desc { text-align: left; padding-left: 1.25rem; padding-right: 0.75rem; }
      .inv-th--num  { text-align: right; }
      .inv-th--amt  { text-align: right; padding-right: 1.25rem; }

      .inv-tr { border-bottom: 1px solid #f8fafc; }
      .inv-tr:last-child { border-bottom: none; }

      .inv-td {
        padding: 0.875rem 0.75rem;
        font-size: 0.8125rem;
        color: #6b7280;
        font-variant-numeric: tabular-nums;
      }

      .inv-td--desc {
        padding-left: 1.25rem;
        padding-right: 0.75rem;
        font-size: 0.8125rem;
        font-weight: 500;
        color: #1f2937;
        font-variant-numeric: normal;
      }

      .inv-td--num { text-align: right; }

      .inv-td--amt {
        text-align: right;
        padding-right: 1.25rem;
        font-size: 0.8125rem;
        font-weight: 600;
        color: #111827;
      }

      /* ── Totals ── */
      .inv-totals-sep {
        height: 1px;
        background: #f1f5f9;
        margin: 0 1.5rem;
      }

      .inv-totals {
        display: flex;
        justify-content: flex-end;
        padding: 1.5rem 2.5rem;
      }

      .inv-totals-inner {
        width: 280px;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .inv-tr-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 2px 0;
        gap: 1.5rem;
      }

      .inv-tr-row--total { padding: 3px 0; }

      .inv-totals-line {
        height: 1px;
        background: #e5e7eb;
        margin: 8px 0;
      }

      .inv-tl {
        font-size: 0.75rem;
        color: #9ca3af;
        font-weight: 500;
      }

      .inv-tl--total {
        font-size: 0.84375rem;
        font-weight: 700;
        color: #111827;
      }

      .inv-tv {
        font-size: 0.78125rem;
        color: #4b5563;
        font-weight: 500;
        font-variant-numeric: tabular-nums;
      }

      .inv-tv--total {
        font-size: 0.875rem;
        font-weight: 700;
        color: #111827;
        letter-spacing: -0.01em;
      }

      .inv-tv--due {
        font-size: 0.75rem;
        font-weight: 600;
        color: #3D47F5;
      }

      .inv-tv--green { color: #16a34a; }

      /* ── Notes / Terms ── */
      .inv-notes-wrap {
        padding: 0 2.5rem 1.75rem;
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }

      .inv-notes-box {
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        padding: 1.25rem 1.5rem;
      }

      .inv-notes-text {
        font-size: 0.78125rem;
        color: #4b5563;
        line-height: 1.6;
        white-space: pre-wrap;
      }

      /* ── CTA ── */
      .inv-cta { padding: 0 2.5rem 1.5rem; }

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

      /* ── Footer ── */
      .inv-footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        border-top: 1px solid #f1f5f9;
        padding: 1rem 2.5rem;
      }

      .inv-footer-label {
        font-size: 0.59375rem;
        font-weight: 700;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: #9ca3af;
        margin-bottom: 3px;
      }

      .inv-footer-sub {
        font-size: 0.6875rem;
        color: #9ca3af;
      }

      .inv-footer-date {
        font-size: 0.65625rem;
        color: #d1d5db;
      }

      /* ── Error state ── */
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

      .inv-error-title { font-size: 1.125rem; font-weight: 700; color: #111827; margin-bottom: 0.5rem; }
      .inv-error-body  { font-size: 0.875rem; color: #6b7280; line-height: 1.6; }

      @media (max-width: 600px) {
        .inv-page { padding: 1rem 0.75rem 3rem; }
        .inv-header { padding: 1.5rem 1.25rem 1.25rem; }
        .inv-title { font-size: 1.75rem; }
        .inv-strip-divider { margin: 0 1.25rem; }
        .inv-billing { padding: 1rem 1.25rem; flex-wrap: wrap; }
        .inv-dates { flex-wrap: wrap; gap: 1rem; }
        .inv-date-col { text-align: left; }
        .inv-table-wrap { padding: 0 0.5rem; }
        .inv-th--desc, .inv-td--desc { padding-left: 0.75rem; }
        .inv-th--amt, .inv-td--amt { padding-right: 0.75rem; }
        .inv-totals-sep { margin: 0 0.75rem; }
        .inv-totals { padding: 1rem 1.25rem; }
        .inv-totals-inner { width: 100%; }
        .inv-notes-wrap { padding: 0 1.25rem 1.25rem; }
        .inv-cta { padding: 0 1.25rem 1.25rem; }
        .inv-footer { padding: 0.875rem 1.25rem; }
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

  defp status_class("open", true),        do: "overdue"
  defp status_class("open", false),       do: "open"
  defp status_class("partially_paid", _), do: "partial"
  defp status_class("paid", _),           do: "paid"
  defp status_class("void", _),           do: "void"
  defp status_class(_, _),               do: "open"

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
