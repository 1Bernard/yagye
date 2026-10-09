# frozen_string_literal: true

module Checkout
  module PaymentLinks
    class ShowView < ApplicationComponent
      include UI::Theme

      CURRENCY_SYMBOLS = { "GHS" => "GH₵", "NGN" => "₦", "KES" => "KSh", "XOF" => "CFA", "USD" => "$" }.freeze

      METHOD_META = {
        "mobile_money"  => { label: "Mobile Money",  icon: "📱" },
        "card"          => { label: "Card",           icon: "💳" },
        "bank_transfer" => { label: "Bank transfer",  icon: "🏦" }
      }.freeze

      def initialize(link:, analytics: {})
        @link      = link
        @analytics = analytics
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payment_links,
          title:      @link["description"] || @link["id"],
          breadcrumbs: [
            { label: "Payment Links", href: payment_links_path },
            { label: @link["description"] || @link["id"].to_s.first(16) }
          ],
          padded: false
        ) do
          canvas_styles

          div(class: "relative h-full overflow-hidden") do
            div(id: "pl-show-canvas", class: "absolute inset-0")
            floating_toolbar
            div(class: "absolute top-[76px] left-0 right-0 bottom-0") do
              details_panel
              preview_area
            end
          end
        end
      end

      private

      # ── Canvas background ─────────────────────────────────────────────────────

      def canvas_styles
        style do
          raw safe(%(
            #pl-show-canvas {
              background-color: #f8fafc;
              background-image: radial-gradient(circle, #d1d5db 1px, transparent 1px);
              background-size: 24px 24px;
            }
          ))
        end
      end

      # ── Floating toolbar ──────────────────────────────────────────────────────

      def floating_toolbar
        div(
          class: "absolute top-4 left-1/2 -translate-x-1/2 z-30 flex items-center gap-[6px] " \
                 "bg-white border border-gray-200/80 rounded-2xl px-[10px] py-[7px] " \
                 "shadow-[0_4px_24px_rgba(0,0,0,0.08)] select-none"
        ) do
          a(href: payment_links_path,
            class: "flex items-center justify-center w-8 h-8 rounded-xl " \
                   "hover:bg-gray-100 text-gray-400 hover:text-gray-700 transition-colors flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:chev_left, class: "w-full h-full") }
          end

          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

          p(class: "text-[13.5px] font-semibold text-gray-900 px-1 max-w-[200px] truncate") do
            plain @link["description"] || @link["id"]
          end

          if @link["active"]
            span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-green-50 text-green-700 border border-green-200/60") do
              plain "Active"
            end
          else
            span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500") do
              plain "Inactive"
            end
          end

          span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500") do
            plain (@link["mode"] || "simulation").capitalize
          end

          # Mode badge — tells the user they are viewing, not editing
          span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500 " \
                      "flex items-center gap-[4px]") do
            span(class: "flex w-[10px] h-[10px]") { render UI::Icon.new(:eye, class: "w-full h-full") }
            plain "Overview"
          end

          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

          if @link["kind"] == "invoice"
            a(href: invoices_path,
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                     "border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors no-underline") do
              render UI::Icon.new(:file, class: "w-3.5 h-3.5")
              plain "Invoices"
            end
          end

          a(href: payment_link_layout_path(@link["id"]),
            class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                   "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors no-underline") do
            render UI::Icon.new(:edit, class: "w-3.5 h-3.5")
            plain @link["kind"] == "invoice" ? "Edit checkout" : "Edit layout"
          end

          if @link["active"] && @link["kind"] != "invoice"
            div(class: "w-px h-5 bg-gray-200 flex-shrink-0")
            form(action: deactivate_payment_link_path(@link["id"]), method: "post", style: "display:contents") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(
                type:  "submit",
                class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                       "border border-red-200 text-red-600 hover:bg-red-50 transition-colors cursor-pointer",
                data:  { confirm: "Deactivate this link? Customers won't be able to use it." }
              ) do
                render UI::Icon.new(:x, class: "w-3.5 h-3.5")
                plain "Deactivate"
              end
            end
          end
        end
      end

      # ── Left details panel ────────────────────────────────────────────────────

      def details_panel
        div(
          class: "absolute top-5 left-5 bottom-5 z-20 w-[320px] flex flex-col " \
                 "bg-white border border-gray-200/70 rounded-2xl overflow-hidden " \
                 "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]"
        ) do
          panel_header
          div(class: "flex-1 overflow-y-auto") do
            analytics_section
            divider
            link_info_section
            divider
            methods_info_section
            divider
            collect_info_section
            divider
            usage_info_section
          end
        end
      end

      def panel_header
        div(class: "flex items-center justify-between px-4 pt-[14px] pb-[10px] flex-shrink-0") do
          p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Link details" }
          if @link["active"]
            span(class: "flex items-center gap-[4px] text-[10.5px] font-semibold text-green-600") do
              span(class: "w-[6px] h-[6px] rounded-full bg-green-500 flex-shrink-0") { }
              plain "Live"
            end
          else
            span(class: "flex items-center gap-[4px] text-[10.5px] font-semibold text-gray-400") do
              span(class: "w-[6px] h-[6px] rounded-full bg-gray-300 flex-shrink-0") { }
              plain "Inactive"
            end
          end
        end
        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")
      end

      def divider
        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")
      end

      def section_label(text)
        p(class: "text-[9px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2.5") { plain text }
      end

      def detail_row(label, value_text = nil, &block)
        div(class: "flex flex-col gap-[3px] mb-[11px]") do
          span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain label }
          if block
            div(class: "text-[12.5px] text-gray-700", &block)
          else
            p(class: "text-[12.5px] text-gray-700") { plain value_text.to_s.presence || "—" }
          end
        end
      end

      # ── Conversion analytics ──────────────────────────────────────────────────

      def analytics_section
        views       = @analytics[:views].to_i
        completions = @analytics[:completions].to_i
        expired     = @analytics[:expired].to_i
        rate        = views > 0 ? (completions * 100.0 / views).round : 0

        div(class: "px-4 pt-3 pb-4") do
          section_label("Analytics")

          div(class: "grid grid-cols-3 gap-2 mb-3") do
            analytic_stat("Views",     views.to_s,       "#3D47F5")
            analytic_stat("Completed", completions.to_s, "#16a34a")
            analytic_stat("Expired",   expired.to_s,     "#d97706")
          end

          if views > 0
            div(class: "flex items-center gap-2 mb-1.5") do
              span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Conversion" }
              span(class: "ml-auto text-[12px] font-bold tabular-nums",
                   style: "color:#{rate >= 50 ? "#16a34a" : rate >= 20 ? "#d97706" : "#dc2626"}") do
                plain "#{rate}%"
              end
            end
            div(class: "w-full h-1 rounded-full overflow-hidden bg-gray-100") do
              div(class: "h-full rounded-full",
                  style: "width:#{rate}%;background:#{rate >= 50 ? "#16a34a" : rate >= 20 ? "#d97706" : "#dc2626"}")
            end
          else
            p(class: "text-[11px] text-gray-400 italic") { plain "Share the link to see activity here." }
          end
        end
      end

      def analytic_stat(label_text, value, color)
        div(class: "flex flex-col items-center gap-[3px] rounded-[10px] py-[10px]",
            style: "background:#{color}0d;border:1px solid #{color}20") do
          span(class: "text-[18px] font-extrabold tabular-nums leading-tight", style: "color:#{color}") do
            plain value
          end
          span(class: "text-[8.5px] font-bold uppercase tracking-widest text-gray-400") { plain label_text }
        end
      end

      # ── Link info ─────────────────────────────────────────────────────────────

      def link_info_section
        sym   = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed = @link["kind"] == "fixed_amount"

        div(class: "px-4 pt-3 pb-4") do
          section_label("Link details")

          detail_row("Description", @link["description"].presence || "—")

          if fixed
            detail_row("Amount") do
              p(class: "text-[20px] font-extrabold text-gray-900 tabular-nums leading-tight") do
                span(class: "text-[13px] font-bold text-gray-400 mr-0.5") { plain sym }
                plain "%.2f" % (@link["amount"].to_i / 100.0)
              end
            end
          else
            detail_row("Payment type") do
              span(class: "inline-flex px-2 py-[3px] rounded-[6px] text-[11.5px] font-semibold bg-gray-100 text-gray-600") do
                plain "Open amount"
              end
            end
          end

          detail_row("Currency", "#{@link["currency"]} (#{sym})")

          detail_row("Created") do
            plain @link["inserted_at"] ? (Time.parse(@link["inserted_at"]).strftime("%d %b %Y") rescue "—") : "—"
          end
        end
      end

      # ── Payment methods ───────────────────────────────────────────────────────

      def methods_info_section
        methods = Array(@link["allowed_methods"])

        div(class: "px-4 pt-3 pb-4") do
          section_label("Payment methods")
          if methods.any?
            div(class: "flex flex-wrap gap-[6px]") do
              methods.each do |m|
                meta = METHOD_META[m] || { label: m.humanize, icon: "•" }
                span(class: "flex items-center gap-[5px] px-2.5 py-[5px] rounded-[8px] " \
                            "bg-gray-50 border border-gray-100 text-[11.5px] font-medium text-gray-700") do
                  span(class: "text-[13px]") { plain meta[:icon] }
                  plain meta[:label]
                end
              end
            end
          else
            p(class: "text-[12px] text-gray-400 italic") { plain "No methods configured" }
          end
        end
      end

      # ── Collect from customer ─────────────────────────────────────────────────

      def collect_info_section
        fields = [
          [ "collect_email", "Email address" ],
          [ "collect_phone", "Phone number" ],
          [ "collect_name",  "Full name" ]
        ]
        active_fields = fields.select { |f, _| @link[f] }

        div(class: "px-4 pt-3 pb-4") do
          section_label("Collect from customer")
          if active_fields.any?
            div(class: "flex flex-col gap-[6px]") do
              active_fields.each do |_, label_text|
                div(class: "flex items-center gap-2") do
                  span(class: "w-[14px] h-[14px] rounded-full bg-green-500/10 border border-green-200 " \
                              "flex-shrink-0 flex items-center justify-center") do
                    span(class: "text-[8px] text-green-600 font-bold") { plain "✓" }
                  end
                  p(class: "text-[12px] font-medium text-gray-700") { plain label_text }
                end
              end
            end
          else
            p(class: "text-[12px] text-gray-400 italic") { plain "No fields collected" }
          end
        end
      end

      # ── Usage & expiry ────────────────────────────────────────────────────────

      def usage_info_section
        use_count = @link["use_count"].to_i
        max_uses  = @link["max_uses"]

        div(class: "px-4 pt-3 pb-5") do
          section_label("Usage & expiry")

          if @link["reusable"]
            detail_row("Uses") do
              div(class: "flex items-baseline gap-1.5 mb-1") do
                span(class: "text-[18px] font-extrabold text-gray-900 tabular-nums") { plain use_count.to_s }
                if max_uses
                  span(class: "text-[11.5px] text-gray-400") { plain "of #{max_uses}" }
                else
                  span(class: "text-[11.5px] text-gray-400") { plain "uses" }
                end
              end
              if max_uses
                pct = [ (use_count.to_f / max_uses * 100).round, 100 ].min
                fill_color = pct >= 90 ? "#ef4444" : pct >= 60 ? "#f59e0b" : "#3D47F5"
                div(class: "w-full h-1 bg-gray-100 rounded-full overflow-hidden") do
                  div(class: "h-full rounded-full", style: "width:#{pct}%;background:#{fill_color}")
                end
              end
            end
          else
            detail_row("Type", "Single use")
          end

          if @link["expires_at"]
            detail_row("Expires") do
              plain Time.parse(@link["expires_at"]).strftime("%d %b %Y at %H:%M") rescue @link["expires_at"]
            end
          else
            detail_row("Expires", "No expiry")
          end
        end
      end

      # ── Right preview area ────────────────────────────────────────────────────

      def preview_area
        url = @link["checkout_url"].to_s

        div(
          class: "absolute top-5 right-0 bottom-0 overflow-y-auto",
          style: "left: 365px"
        ) do
          div(class: "min-h-full pb-10 flex flex-col items-center pt-0 px-5") do
            share_pill(url)
            checkout_preview_card
          end
        end

        copy_script(url)
      end

      # ── Share pill (matches layout page pattern) ──────────────────────────────

      def share_pill(url)
        div(
          class: "w-full max-w-[460px] flex items-center gap-0 mb-3 " \
                 "bg-white border border-gray-200/80 rounded-2xl overflow-hidden " \
                 "shadow-[0_4px_20px_rgba(0,0,0,0.06)]"
        ) do
          # Label + URL
          div(class: "flex items-center gap-2.5 flex-1 min-w-0 px-4 py-[9px]") do
            span(class: "text-[10px] font-bold uppercase tracking-[0.1em] text-gray-300 flex-shrink-0") do
              plain "Share"
            end
            span(class: "w-px h-3 bg-gray-200 flex-shrink-0")
            a(
              href:   url,
              target: "_blank",
              rel:    "noopener noreferrer",
              class:  "font-mono text-[11px] text-[#3D47F5] hover:underline truncate"
            ) { plain url }
          end

          # Separator
          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          # Copy
          button(
            type:    "button",
            id:      "pl-copy-btn",
            class:   "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                     "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors cursor-pointer",
            data:    { url: url }
          ) do
            render UI::Icon.new(:copy, class: "w-3.5 h-3.5")
            plain "Copy"
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          # WhatsApp
          a(
            href:   "https://wa.me/?text=#{CGI.escape("#{@link["description"].presence || "Pay here"}: #{url}")}",
            target: "_blank",
            rel:    "noopener noreferrer",
            class:  "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                    "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors no-underline"
          ) do
            span(class: "text-[13px] leading-none") { plain "💬" }
            plain "WhatsApp"
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          # QR — opens the dedicated counter display page in a new tab via window.open()
          #      so the display tab can call window.close() to return here cleanly
          button(
            type:  "button",
            id:    "pl-qr-btn",
            data:  { url: payment_link_display_path(@link["id"]) },
            class: "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                   "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors cursor-pointer border-0 bg-transparent"
          ) do
            render UI::Icon.new(:qr_code, class: "w-3.5 h-3.5")
            plain "QR"
          end
        end
      end

      # ── Copy script ───────────────────────────────────────────────────────────

      def copy_script(url)
        script do
          raw safe(<<~JS)
            (function () {
              var copyBtn = document.getElementById('pl-copy-btn');
              if (copyBtn) {
                copyBtn.addEventListener('click', function () {
                  navigator.clipboard.writeText(#{url.to_json}).then(function () {
                    copyBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>Copied</span>';
                    copyBtn.style.color = '#16a34a';
                    setTimeout(function () {
                      copyBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg><span>Copy</span>';
                      copyBtn.style.color = '';
                    }, 2000);
                  }).catch(function () {
                    copyBtn.innerHTML = '<span>Copy</span>';
                  });
                });
              }

              // Open QR display page via window.open() so the display tab can close itself cleanly
              var qrBtn = document.getElementById('pl-qr-btn');
              if (qrBtn) {
                qrBtn.addEventListener('click', function () {
                  window.open(qrBtn.dataset.url, '_blank');
                });
              }
            })();
          JS
        end
      end

      # ── Checkout preview card ─────────────────────────────────────────────────

      def checkout_preview_card
        sym       = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed     = @link["kind"] == "fixed_amount"
        amt       = @link["amount"].to_i
        methods   = Array(@link["allowed_methods"])
        saved_logo    = @link.dig("checkout_layout", "logo_url").to_s
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        initials      = merchant_name.split.first(2).map { |w| w[0].upcase }.join

        div(class: "w-full max-w-[460px]") do
          div(
            class: "bg-white rounded-2xl overflow-hidden " \
                   "shadow-[0_12px_40px_rgba(0,0,0,0.10),0_2px_10px_rgba(0,0,0,0.05)] " \
                   "border border-gray-100/80"
          ) do
            # Brand bar
            div(class: "flex items-center gap-2.5 px-6 py-4 border-b border-gray-50") do
              if saved_logo.present?
                img(src: saved_logo, alt: "Logo",
                    class: "w-7 h-7 rounded-lg object-cover border border-gray-100 flex-shrink-0")
              else
                div(class: "w-7 h-7 rounded-lg bg-[#3D47F5] flex items-center justify-center flex-shrink-0") do
                  span(class: "text-[10px] font-bold text-white") { plain initials }
                end
              end
              p(class: "text-[12.5px] font-semibold text-gray-700") { plain merchant_name }
              span(class: "ml-auto text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-400") do
                plain (@link["mode"] || "simulation").capitalize
              end
            end

            # Amount + description
            div(class: "px-6 pt-6 pb-5") do
              if fixed && amt > 0
                p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1") { plain "Total" }
                p(class: "text-[32px] font-extrabold text-gray-900 leading-none tracking-tight tabular-nums mb-3") do
                  span(class: "text-[17px] font-bold text-gray-400 mr-1") { plain sym }
                  plain "%.2f" % (amt / 100.0)
                end
              else
                p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "Amount" }
                div(class: "h-11 bg-gray-50 border border-gray-200 rounded-[10px] flex items-center px-3 mb-3") do
                  p(class: "text-[12.5px] text-gray-300") { plain "Enter amount..." }
                end
              end
              p(class: "text-[13.5px] font-medium text-gray-500 leading-snug") do
                plain @link["description"].presence || "Payment"
              end
            end

            div(class: "h-px bg-gray-100 mx-6")

            # Payment methods
            div(class: "px-6 py-5") do
              p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-3") { plain "Pay with" }
              div(class: "flex flex-wrap gap-2") do
                methods.each do |m|
                  meta = METHOD_META[m] || { label: m.humanize, icon: "•" }
                  div(class: "flex items-center gap-1.5 px-3 py-[7px] rounded-[10px] border border-gray-200 " \
                             "text-[12px] font-medium text-gray-700 bg-white") do
                    span(class: "text-[14px]") { plain meta[:icon] }
                    plain meta[:label]
                  end
                end
              end
            end

            # Collect fields
            collect_any = @link["collect_email"] || @link["collect_phone"] || @link["collect_name"]
            if collect_any
              div(class: "h-px bg-gray-100 mx-6")
              div(class: "px-6 py-5 flex flex-col gap-2.5") do
                preview_input_placeholder("Full name",     "text",  "Your name")     if @link["collect_name"]
                preview_input_placeholder("Email address", "email", "you@example.com") if @link["collect_email"]
                preview_input_placeholder("Phone number",  "tel",   "+233 24 000 0000") if @link["collect_phone"]
              end
            end

            # CTA
            div(class: "px-6 pb-6") do
              pay_label = fixed && amt > 0 ? "Pay #{sym}#{"%.2f" % (amt / 100.0)}" : "Pay now"
              div(class: "w-full py-3.5 rounded-[10px] bg-[#3D47F5] flex items-center justify-center " \
                         "text-[13.5px] font-bold text-white cursor-default select-none") { plain pay_label }
            end

            # Footer
            div(class: "px-6 pb-5 flex items-center justify-center gap-[5px]") do
              span(class: "text-[10px] text-gray-300") { plain "Powered by" }
              span(class: "text-[10px] font-bold text-[#3D47F5]/60") { plain "Yagye" }
            end
          end
        end
      end

      def preview_input_placeholder(label_text, _type, placeholder)
        div do
          p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") { plain label_text }
          div(class: "w-full h-[38px] border border-gray-200 rounded-[10px] px-3 flex items-center " \
                     "text-[12.5px] text-gray-300") { plain placeholder }
        end
      end
    end
  end
end
