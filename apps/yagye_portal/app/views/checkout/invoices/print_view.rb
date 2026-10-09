# frozen_string_literal: true

module Checkout
  module Invoices
    class PrintView < ApplicationComponent
      include UI::Theme

      def initialize(invoice:, logo_url: nil)
        @inv      = invoice
        @logo_url = logo_url
      end

      def view_template
        doctype
        html(lang: "en") do
          head do
            meta(charset: "UTF-8")
            meta(name: "viewport", content: "width=device-width, initial-scale=1")
            title { plain "Invoice #{@inv["number"] || @inv["id"]}" }
            page_styles
          end
          body do
            div(class: "page-wrapper") do
              ext_bar
              div(class: "invoice-card") do
                doc_header
                billing_strip
                document_divider(dashed: false)
                line_items_section
                totals_section
                notes_footer if @inv["notes"].present? || @inv["terms"].present?
                doc_footer
                card_actions
              end
            end
            print_script
          end
        end
      end

      private

      # ── Styles ────────────────────────────────────────────────────────────────

      def page_styles
        style do
          raw safe(<<~CSS)
            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              background: #f2f3f7;
              color: #111827;
              -webkit-print-color-adjust: exact;
              print-color-adjust: exact;
            }
            a { color: inherit; text-decoration: none; }
            table { border-collapse: collapse; width: 100%; }

            /* External action bar — hidden on print */
            .ext-bar {
              width: 100%;
              max-width: 760px;
              margin-bottom: 12px;
              display: flex;
              align-items: center;
              justify-content: space-between;
            }
            .btn-back {
              display: inline-flex;
              align-items: center;
              gap: 5px;
              font-size: 12px;
              font-weight: 500;
              color: #9ca3af;
              text-decoration: none;
              transition: color 0.15s;
            }
            .btn-back:hover { color: #374151; }
            .mode-badge {
              font-size: 10.5px;
              font-weight: 600;
              padding: 3px 10px;
              border-radius: 999px;
              background: rgba(209,213,219,0.7);
              color: #6b7280;
            }

            /* Card action row — hidden on print */
            .card-actions {
              padding: 16px 40px;
              border-top: 1px solid #f1f5f9;
              display: flex;
              align-items: center;
            }
            .btn-print {
              flex: 1;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              gap: 6px;
              padding: 9px 16px;
              border-radius: 10px;
              background: #3D47F5;
              color: white;
              font-size: 12.5px;
              font-weight: 600;
              border: none;
              cursor: pointer;
              transition: background 0.15s;
            }
            .btn-print:hover { background: #2e38d4; }

            /* Page layout */
            .page-wrapper {
              min-height: 100vh;
              padding: 24px;
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
            }
            .invoice-card {
              background: white;
              width: 100%;
              max-width: 760px;
              border-radius: 16px;
              overflow: hidden;
              box-shadow: 0 8px 40px rgba(0,0,0,0.09), 0 2px 12px rgba(0,0,0,0.05);
            }

            /* Dividers */
            .divider { border: none; border-top: 1px solid #f1f5f9; margin: 0; }
            .divider-dashed { border: none; border-top: 1px dashed #e5e7eb; margin: 0; }

            /* Totals box */
            .amount-due-box {
              background: rgba(61,71,245,0.06);
              border-radius: 12px;
              padding: 12px 16px;
              display: flex;
              align-items: center;
              justify-content: space-between;
              margin-top: 12px;
            }

            /* Footer text */
            .doc-footer {
              padding: 16px 40px;
              border-top: 1px solid #f1f5f9;
              display: flex;
              align-items: center;
              justify-content: space-between;
              font-size: 10.5px;
              color: #9ca3af;
            }

            @media print {
              @page { margin: 0; size: A4 portrait; }
              body { background: white !important; }
              .ext-bar { display: none !important; }
              .card-actions { display: none !important; }
              .page-wrapper {
                padding: 0 !important;
                min-height: 0 !important;
                background: white !important;
                justify-content: flex-start !important;
              }
              .invoice-card {
                max-width: 100% !important;
                border-radius: 0 !important;
                box-shadow: none !important;
              }
            }
          CSS
        end
      end

      # ── External action bar (above card, hidden on print) ────────────────────

      def ext_bar
        inv_path = helpers.invoice_path(@inv["id"]) rescue "#"
        div(class: "ext-bar") do
          a(id: "pv-back-btn", href: inv_path, class: "btn-back") do
            plain "← Back to portal"
          end
          span(class: "mode-badge") do
            plain (@inv["mode"] || "simulation").capitalize
          end
        end
      end

      # ── Card action row (inside card, hidden on print) ────────────────────────

      def card_actions
        div(class: "card-actions") do
          button(id: "pv-print-btn", type: "button", class: "btn-print") do
            plain "Print / Save PDF"
          end
        end
      end

      # ── Document header ──────────────────────────────────────────────────────

      def doc_header
        merchant_name = @inv.dig("merchant", "name").presence ||
                        @inv["merchant_code"].to_s
        initials = merchant_name.split.first(2).map { |w| w[0].upcase }.join.presence || "Y"

        div(style: "display:flex;align-items:flex-start;justify-content:space-between;" \
                   "padding:36px 40px 28px;border-bottom:1px solid #f1f5f9;gap:24px") do
          # Left: logo + merchant
          div(style: "display:flex;align-items:center;gap:14px") do
            if @logo_url.present?
              img(src: @logo_url, alt: "Logo",
                  style: "width:48px;height:48px;border-radius:10px;object-fit:cover;" \
                         "border:1px solid #f1f5f9;flex-shrink:0")
            else
              div(style: "width:48px;height:48px;border-radius:10px;" \
                         "background:#3D47F5;display:flex;align-items:center;" \
                         "justify-content:center;flex-shrink:0;" \
                         "box-shadow:0 2px 8px rgba(61,71,245,0.30)") do
                span(style: "font-size:13px;font-weight:800;color:white;letter-spacing:-0.5px") do
                  plain initials
                end
              end
            end
            div do
              p(style: "font-size:14px;font-weight:700;color:#111827;line-height:1.3") do
                plain merchant_name.presence || "Your business"
              end
              p(style: "font-size:11.5px;color:#9ca3af;margin-top:2px") do
                plain @inv["merchant_code"].to_s
              end
            end
          end

          # Right: INVOICE label + number + state badge
          div(style: "display:flex;flex-direction:column;align-items:flex-end;gap:6px") do
            p(style: "font-size:28px;font-weight:800;color:#3D47F5;letter-spacing:-0.5px;line-height:1") do
              plain "INVOICE"
            end
            p(style: "font-size:14px;font-weight:600;color:#6b7280;font-family:monospace") do
              plain @inv["number"] || @inv["id"].to_s.first(12)
            end
            state_chip(@inv["state"])
          end
        end
      end

      def state_chip(state)
        cfg = case state
        when "draft"            then [ "#f3f4f6", "#6b7280", "Draft" ]
        when "open"             then [ "rgba(61,71,245,0.08)", "#3D47F5", "Open" ]
        when "partially_paid"   then [ "rgba(234,179,8,0.10)", "#a16207", "Partial" ]
        when "paid"             then [ "rgba(22,163,74,0.10)", "#15803d", "Paid" ]
        when "overdue"          then [ "rgba(220,38,38,0.10)", "#b91c1c", "Overdue" ]
        when "void"             then [ "#f3f4f6", "#9ca3af", "Void" ]
        else                         [ "#f3f4f6", "#6b7280", (state || "unknown").capitalize ]
        end

        span(style: "display:inline-block;font-size:10.5px;font-weight:700;letter-spacing:0.06em;" \
                    "text-transform:uppercase;padding:3px 9px;border-radius:999px;" \
                    "background:#{cfg[0]};color:#{cfg[1]}") do
          plain cfg[2]
        end
      end

      # ── Billing strip ────────────────────────────────────────────────────────

      def billing_strip
        merchant_name = @inv.dig("merchant", "name").presence ||
                        @inv["merchant_code"].to_s.presence || "Your business"

        div(style: "display:grid;grid-template-columns:1fr 1fr 1fr 1fr;" \
                   "gap:0;padding:24px 40px;background:#f8fafc;border-bottom:1px solid #f1f5f9") do
          strip_cell("Issue date", fmt_date(@inv["issue_date"]))
          strip_cell("Due date",   fmt_date(@inv["due_date"]))
          strip_cell("From",       merchant_name)
          strip_cell("Bill to",    @inv["customer_reference"].presence || "—")
        end
      end

      def strip_cell(label, value)
        div(style: "padding: 0 12px 0 0") do
          p(style: "font-size:9.5px;font-weight:700;text-transform:uppercase;letter-spacing:0.1em;" \
                   "color:#9ca3af;margin-bottom:5px") do
            plain label
          end
          p(style: "font-size:12.5px;font-weight:600;color:#1f2937;line-height:1.4") do
            plain value || "—"
          end
        end
      end

      # ── Line items ───────────────────────────────────────────────────────────

      def line_items_section
        items    = Array(@inv["line_items"])
        currency = @inv["currency"] || "GHS"

        div do
          # Branded table header
          div(style: "display:grid;grid-template-columns:1fr 60px 110px 70px 130px;column-gap:16px;" \
                     "padding:10px 40px;background:rgba(61,71,245,0.05);" \
                     "border-bottom:1px solid rgba(61,71,245,0.10)") do
            th_cell("Description", align: "left")
            th_cell("Qty",         align: "right")
            th_cell("Unit price",  align: "right")
            th_cell("Tax",         align: "right")
            th_cell("Amount",      align: "right")
          end

          items.each_with_index do |item, idx|
            unit   = item["unit_amount"].to_i
            qty    = item["quantity"].to_f
            bps    = item["tax_rate_bps"].to_i
            amount = (unit * qty + unit * qty * bps / 10_000.0).round
            bg     = idx.odd? ? "#f9fafb" : "white"

            div(style: "display:grid;grid-template-columns:1fr 60px 110px 70px 130px;column-gap:16px;" \
                       "padding:11px 40px;background:#{bg};" \
                       "border-bottom:1px solid #f8fafc") do
              td_cell(item["description"] || "—", style: "font-size:13px;color:#111827")
              td_cell(qty % 1 == 0 ? qty.to_i.to_s : ("%.2f" % qty),
                      align: "right", style: "color:#6b7280")
              td_cell("#{currency} #{"%.2f" % (unit / 100.0)}",
                      align: "right", style: "color:#6b7280;font-family:monospace")
              td_cell(bps > 0 ? "#{bps / 100.0}%" : "—",
                      align: "right", style: "color:#9ca3af")
              td_cell("#{currency} #{"%.2f" % (amount / 100.0)}",
                      align: "right", style: "font-weight:600;color:#111827;font-family:monospace")
            end
          end
        end
      end

      def th_cell(text, align: "left")
        span(style: "font-size:9.5px;font-weight:700;text-transform:uppercase;letter-spacing:0.08em;" \
                    "color:#6b7280;text-align:#{align};display:block") do
          plain text
        end
      end

      def td_cell(text, align: "left", style: "")
        span(style: "font-size:12.5px;text-align:#{align};display:block;#{style}") do
          plain text
        end
      end

      # ── Totals ───────────────────────────────────────────────────────────────

      def totals_section
        subtotal   = @inv["subtotal_amount"].to_i
        tax        = @inv["tax_amount"].to_i
        discount   = @inv["discount_amount"].to_i
        total      = @inv["total_amount"].to_i
        amount_due = @inv["amount_due"].to_i
        paid       = @inv["amount_paid"].to_i

        div(style: "display:flex;justify-content:flex-end;padding:24px 40px;" \
                   "border-top:1px solid #f1f5f9") do
          div(style: "width:280px;display:flex;flex-direction:column;gap:4px") do
            totals_row("Subtotal", fmt_money(subtotal))
            totals_row("Tax",      fmt_money(tax))                   if tax > 0
            totals_row("Discount", "− #{fmt_money(discount)}")       if discount > 0
            totals_row("Total",    fmt_money(total), bold: true)
            totals_row("Paid",     "− #{fmt_money(paid)}", color: "#16a34a") if paid > 0

            div(class: "amount-due-box") do
              span(style: "font-size:12px;font-weight:700;color:#3D47F5") { plain "Amount due" }
              span(style: "font-size:16px;font-weight:800;color:#3D47F5;font-family:monospace") do
                plain fmt_money(amount_due)
              end
            end
          end
        end
      end

      def totals_row(label, value, bold: false, color: "#6b7280")
        div(style: "display:flex;align-items:center;justify-content:space-between;padding:2px 0") do
          span(style: "font-size:12px;#{bold ? 'font-weight:600;color:#1f2937' : "color:#9ca3af"}") do
            plain label
          end
          span(style: "font-size:12.5px;font-family:monospace;#{bold ? 'font-weight:700;color:#111827' : "color:#{color}"}") do
            plain value
          end
        end
      end

      # ── Notes footer ─────────────────────────────────────────────────────────

      def notes_footer
        div(style: "border-top:1px dashed #e5e7eb;margin:0 40px")
        div(style: "display:flex;flex-direction:column;gap:20px;padding:24px 40px") do
          if @inv["notes"].present?
            div do
              p(style: "font-size:9.5px;font-weight:700;text-transform:uppercase;letter-spacing:0.1em;" \
                       "color:#9ca3af;margin-bottom:6px") { plain "Notes" }
              p(style: "font-size:12.5px;color:#4b5563;line-height:1.6") { plain @inv["notes"] }
            end
          end
          if @inv["terms"].present?
            div do
              p(style: "font-size:9.5px;font-weight:700;text-transform:uppercase;letter-spacing:0.1em;" \
                       "color:#9ca3af;margin-bottom:6px") { plain "Terms & conditions" }
              p(style: "font-size:12.5px;color:#4b5563;line-height:1.6") { plain @inv["terms"] }
            end
          end
        end
      end

      # ── Document footer ──────────────────────────────────────────────────────

      def doc_footer
        div(class: "doc-footer") do
          span { plain "Generated #{Time.now.strftime("%d %b %Y at %H:%M")}" }
          span { plain "Payment powered by Yagye" }
        end
      end

      # ── Dividers ─────────────────────────────────────────────────────────────

      def document_divider(dashed: true)
        hr(class: dashed ? "divider-dashed" : "divider")
      end

      # ── Scripts ──────────────────────────────────────────────────────────────

      def print_script
        inv_path = helpers.invoice_path(@inv["id"]) rescue "#"
        script do
          raw safe(<<~JS)
            (function () {
              document.getElementById('pv-print-btn')?.addEventListener('click', function () {
                window.print();
              });

              var backBtn = document.getElementById('pv-back-btn');
              if (backBtn && window.opener) {
                backBtn.addEventListener('click', function (e) {
                  e.preventDefault();
                  window.close();
                });
              }
            })();
          JS
        end
      end

      # ── Helpers ──────────────────────────────────────────────────────────────

      def fmt_money(minor_units, currency: @inv["currency"] || "GHS")
        "#{currency} #{"%.2f" % (minor_units / 100.0)}"
      end

      def fmt_date(val)
        return "—" unless val.present?
        (Date.parse(val) rescue val).then { |d| d.respond_to?(:strftime) ? d.strftime("%d %b %Y") : d }
      end
    end
  end
end
