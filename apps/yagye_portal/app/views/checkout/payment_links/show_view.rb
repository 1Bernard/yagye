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

      def initialize(link:)
        @link = link
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

          p(class: "text-[13.5px] font-semibold text-gray-900 px-1 max-w-[180px] truncate") do
            plain @link["description"] || @link["id"]
          end

          # Status badge
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

          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

          # Copy link button
          button(
            type:  "button",
            id:    "pl-copy-btn",
            class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                   "border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors cursor-pointer",
            data:  { url: @link["checkout_url"].to_s }
          ) do
            render UI::Icon.new(:copy, class: "w-3.5 h-3.5 text-gray-400")
            plain "Copy link"
          end

          # For invoice-kind links: shortcut to the invoices section
          if @link["kind"] == "invoice"
            a(
              href:  invoices_path,
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                     "border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors no-underline"
            ) do
              render UI::Icon.new(:file, class: "w-3.5 h-3.5")
              plain "Invoices"
            end
          end

          # Edit layout / Edit checkout
          a(
            href:  payment_link_layout_path(@link["id"]),
            class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                   "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors no-underline"
          ) do
            render UI::Icon.new(:edit, class: "w-3.5 h-3.5")
            plain @link["kind"] == "invoice" ? "Edit checkout" : "Edit layout"
          end

          # Deactivate (active non-invoice links only)
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

        # Copy script
        script do
          raw safe(<<~JS)
            (function () {
              var btn = document.getElementById('pl-copy-btn');
              if (!btn) return;
              btn.addEventListener('click', function () {
                navigator.clipboard.writeText(btn.dataset.url).then(function () {
                  btn.textContent = 'Copied!';
                  setTimeout(function () {
                    btn.innerHTML = '<svg class="w-3.5 h-3.5 text-gray-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>Copy link';
                  }, 2000);
                });
              });
            })();
          JS
        end
      end

      # ── Left details panel ────────────────────────────────────────────────────

      def details_panel
        div(
          class: "absolute top-5 left-5 bottom-5 z-20 w-[340px] flex flex-col " \
                 "bg-white border border-gray-200/70 rounded-2xl overflow-hidden " \
                 "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]"
        ) do
          div(class: "flex items-center px-4 pt-[14px] pb-[10px] flex-shrink-0") do
            p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-500") { plain "Payment link" }
          end
          div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")

          div(class: "flex-1 overflow-y-auto") do
            link_info_section
            section_divider
            methods_info_section
            section_divider
            collect_info_section
            section_divider
            usage_info_section
          end
        end
      end

      def section_divider
        div(class: "h-px bg-gray-100 mx-3 flex-shrink-0")
      end

      def section_label(text)
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain text }
      end

      def detail_row(label, value_text = nil, &block)
        div(class: "flex flex-col gap-[3px] mb-3") do
          span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain label }
          if block
            div(class: "text-[12.5px] text-gray-700", &block)
          else
            p(class: "text-[12.5px] text-gray-700") { plain value_text.to_s.presence || "—" }
          end
        end
      end

      # ── Link info ─────────────────────────────────────────────────────────────

      def link_info_section
        sym = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed = @link["kind"] == "fixed_amount"

        div(class: "px-4 pt-3 pb-4") do
          section_label("Link details")

          detail_row("Description", @link["description"].presence || "—")

          detail_row("Payment type") do
            span(class: "inline-flex px-2.5 py-1 rounded-[7px] text-[12px] font-semibold " \
                        "#{fixed ? 'bg-[#3D47F5]/[0.07] text-[#3D47F5]' : 'bg-gray-100 text-gray-600'}") do
              plain fixed ? "Fixed amount" : "Open amount"
            end
          end

          if fixed
            detail_row("Amount") do
              p(class: "text-[18px] font-extrabold text-gray-900 tabular-nums leading-tight") do
                span(class: "text-[13px] font-bold text-gray-400 mr-0.5") { plain sym }
                plain "%.2f" % (@link["amount"].to_i / 100.0)
              end
            end
          end

          detail_row("Currency", "#{@link["currency"]} — #{sym}")

          detail_row("Checkout URL") do
            p(class: "text-[11.5px] text-gray-500 font-mono break-all leading-relaxed") do
              plain @link["checkout_url"].to_s
            end
          end
        end
      end

      # ── Payment methods ───────────────────────────────────────────────────────

      def methods_info_section
        methods = Array(@link["allowed_methods"])

        div(class: "px-4 pt-3 pb-4") do
          section_label("Payment methods")
          if methods.any?
            div(class: "flex flex-col gap-1.5") do
              methods.each do |m|
                meta = METHOD_META[m] || { label: m.humanize, icon: "•" }
                div(class: "flex items-center gap-2 px-3 py-2.5 rounded-[10px] bg-gray-50 border border-gray-100") do
                  span(class: "text-[14px]") { plain meta[:icon] }
                  p(class: "text-[12px] font-semibold text-gray-700") { plain meta[:label] }
                  span(class: "ml-auto text-[10px] font-bold text-green-600 uppercase tracking-wide") { plain "On" }
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
          ["collect_email", "Email address"],
          ["collect_phone", "Phone number"],
          ["collect_name",  "Full name"]
        ]
        any_collect = fields.any? { |f, _| @link[f] }

        div(class: "px-4 pt-3 pb-4") do
          section_label("Collect from customer")
          if any_collect
            div(class: "flex flex-col gap-1.5") do
              fields.each do |field, label_text|
                next unless @link[field]
                div(class: "flex items-center gap-2 px-3 py-2 rounded-[10px] bg-gray-50 border border-gray-100") do
                  span(class: "w-[14px] h-[14px] rounded-full bg-green-500 flex-shrink-0 flex items-center justify-center") do
                    span(class: "text-[8px] text-white font-bold") { plain "✓" }
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

          detail_row("Single or reusable") do
            span(class: "text-[12.5px] font-semibold text-gray-700") do
              plain @link["reusable"] ? "Reusable link" : "Single use"
            end
          end

          if @link["reusable"]
            detail_row("Times used") do
              div(class: "flex items-baseline gap-1.5") do
                span(class: "text-[18px] font-extrabold text-gray-900 tabular-nums") { plain use_count.to_s }
                if max_uses
                  span(class: "text-[12px] text-gray-400") { plain "of #{max_uses}" }
                else
                  span(class: "text-[12px] text-gray-400") { plain "uses" }
                end
              end
              if max_uses
                pct = [(use_count.to_f / max_uses * 100).round, 100].min
                fill_color = pct >= 90 ? "bg-red-400" : pct >= 60 ? "bg-amber-400" : "bg-[#3D47F5]"
                div(class: "w-full h-1 bg-gray-100 rounded-full overflow-hidden mt-2") do
                  div(class: "h-full #{fill_color} rounded-full", style: "width: #{pct}%")
                end
              end
            end
          end

          if @link["expires_at"]
            detail_row("Expires") do
              plain Time.parse(@link["expires_at"]).strftime("%d %b %Y at %H:%M") rescue @link["expires_at"]
            end
          else
            detail_row("Expires", "No expiry")
          end

          detail_row("Created") do
            plain @link["inserted_at"] ? (Time.parse(@link["inserted_at"]).strftime("%d %b %Y") rescue "—") : "—"
          end
        end
      end

      # ── Right preview area ────────────────────────────────────────────────────

      def preview_area
        div(
          class: "absolute top-5 right-0 bottom-0 overflow-y-auto",
          style: "left: 385px"
        ) do
          div(class: "min-h-full pb-10 flex flex-col items-center") do
            checkout_preview_card
          end
        end
      end

      def checkout_preview_card
        sym   = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed = @link["kind"] == "fixed_amount"
        amt   = @link["amount"].to_i
        methods = Array(@link["allowed_methods"])

        div(class: "w-full max-w-[420px]") do
          p(class: "text-[9.5px] font-bold uppercase tracking-[0.15em] text-gray-400 text-center mb-4") do
            plain "Customer sees"
          end

          div(
            class: "bg-white rounded-2xl overflow-hidden " \
                   "shadow-[0_12px_40px_rgba(0,0,0,0.10),0_2px_10px_rgba(0,0,0,0.05)]"
          ) do
            # Brand bar
            merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
            initials = merchant_name.split.first(2).map { |w| w[0].upcase }.join
            div(class: "flex items-center gap-2.5 px-6 py-4 border-b border-gray-50") do
              div(class: "w-7 h-7 rounded-lg bg-[#3D47F5] flex items-center justify-center flex-shrink-0") do
                span(class: "text-[10px] font-bold text-white") { plain initials }
              end
              p(class: "text-[12.5px] font-semibold text-gray-700") { plain merchant_name }
            end

            # Amount + description
            div(class: "px-6 pt-6 pb-5") do
              if fixed && amt > 0
                p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1") { plain "Total" }
                p(class: "text-[30px] font-extrabold text-gray-900 leading-none tracking-tight tabular-nums mb-3") do
                  span(class: "text-[16px] font-bold text-gray-400 mr-1") { plain sym }
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

            # Collect fields (if any)
            collect_any = @link["collect_email"] || @link["collect_phone"] || @link["collect_name"]
            if collect_any
              div(class: "h-px bg-gray-100 mx-6")
              div(class: "px-6 py-5 flex flex-col gap-2.5") do
                if @link["collect_name"]
                  preview_input_placeholder("Full name",      "text",  "Your name")
                end
                if @link["collect_email"]
                  preview_input_placeholder("Email address",  "email", "you@example.com")
                end
                if @link["collect_phone"]
                  preview_input_placeholder("Phone number",   "tel",   "+233 24 000 0000")
                end
              end
            end

            # CTA
            div(class: "px-6 pb-6") do
              pay_label = fixed && amt > 0 ? "Pay #{sym}#{"%.2f" % (amt / 100.0)}" : "Pay now"
              div(class: "w-full py-3.5 rounded-[10px] bg-[#3D47F5] flex items-center justify-center " \
                         "text-[13.5px] font-bold text-white cursor-default") { plain pay_label }
            end

            # Footer
            div(class: "px-6 pb-5 flex items-center justify-center gap-[5px]") do
              span(class: "text-[10px] text-gray-300") { plain "Powered by" }
              span(class: "text-[10px] font-bold text-[#3D47F5]/50") { plain "Yagye" }
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
