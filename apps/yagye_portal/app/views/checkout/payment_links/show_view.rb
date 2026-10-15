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

      METHODS = [
        { value: "mobile_money",  label: "Mobile Money",  detail: "MTN MoMo, Telecel, AirtelTigo" },
        { value: "card",          label: "Card",           detail: "Visa and Mastercard" },
        { value: "bank_transfer", label: "Bank transfer",  detail: "Direct bank-to-bank" }
      ].freeze

      def initialize(link:, analytics: {})
        @link      = link
        @analytics = analytics
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :payment_links,
          title:       link_title,
          breadcrumbs: [
            { label: "Payment Links", href: payment_links_path },
            { label: link_title }
          ]
        ) do
          render UI::PageHeader.new(title: link_title, subtitle: @link["url_slug"]) do
            div(class: "flex items-center gap-2") do
              render UI::Chip.new(
                label:  @link["active"] ? "Active" : "Inactive",
                colors: @link["active"] ? STATUS_SUCCESS : STATUS_NEUTRAL
              )
              render UI::Chip.new(label: (@link["mode"] || "simulation").capitalize, colors: STATUS_NEUTRAL)

              if @link["kind"] != "invoice"
                render UI::Button.new(variant: :secondary, href: payment_link_layout_path(@link["id"])) do
                  render UI::Icon.new(:edit, class: ICON_SM)
                  plain "Edit layout"
                end

                if @link["active"]
                  form(action: deactivate_payment_link_path(@link["id"]), method: "post", style: "display:contents") do
                    input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                    render UI::Button.new(
                      variant: :danger,
                      type:    "submit",
                      data:    { turbo_confirm: "Deactivate this link? Customers won't be able to use it." }
                    ) { plain "Deactivate" }
                  end
                end
              end
            end
          end

          render UI::Grid.new(columns: :profile) do
            left_column
            right_column
          end

          copy_script(@link["checkout_url"].to_s)
        end
      end

      private

      def link_title
        @link["description"].presence || @link["id"].to_s.first(16)
      end

      # ── Left column (320px) ───────────────────────────────────────────────────

      def left_column
        div(class: "flex flex-col gap-5") do
          link_details_card
          settings_form_card if @link["kind"] != "invoice" && can?(:create?, :checkout)
        end
      end

      def link_details_card
        sym   = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed = @link["kind"] == "fixed_amount"
        amt   = @link["amount"].to_i

        render UI::Card.new do |c|
          c.header("Link details", icon: :link)
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Type", fixed ? "Fixed amount" : "Open amount")
              list.row("Amount", "#{sym}#{"%.2f" % (amt / 100.0)}") if fixed
              list.row("Currency", "#{@link["currency"]} (#{sym})")
              list.row("Reusable", @link["reusable"] ? "Yes" : "One-time")
              list.row("Created") do
                span(class: TYPE_BODY_MD) do
                  plain @link["inserted_at"] ? (fmt_date(Time.parse(@link["inserted_at"])) rescue "—") : "—"
                end
              end
              if @link["max_uses"]
                list.row("Max uses", "#{@link["use_count"].to_i} / #{@link["max_uses"]}")
              end
              if @link["expires_at"]
                list.row("Expires") do
                  expires_label = begin
                    fmt_date(Time.parse(@link["expires_at"]))
                  rescue
                    @link["expires_at"]
                  end
                  span(class: TYPE_BODY_MD) { plain expires_label }
                end
              end
            end
          end
          c.footer do
            a(href: @link["checkout_url"], target: "_blank", rel: "noopener noreferrer",
              class: "flex-1 min-w-0 font-mono text-[11px] text-[#3D47F5] hover:underline truncate") do
              plain @link["checkout_url"].to_s
            end
            button(
              type:  "button",
              id:    "pl-copy-btn",
              class: "flex-shrink-0 flex items-center gap-[4px] ml-2 text-[11.5px] font-medium " \
                     "text-gray-500 hover:text-gray-800 transition-colors cursor-pointer border-0 bg-transparent",
              data:  { url: @link["checkout_url"] }
            ) do
              render UI::Icon.new(:copy, class: "w-3 h-3")
              plain "Copy"
            end
          end
        end
      end

      def settings_form_card
        methods = Array(@link["allowed_methods"])

        render UI::Card.new do |c|
          c.header("Payment settings", icon: :settings)
          c.body do
            form(action: payment_link_settings_path(@link["id"]), method: "post") do
              input(type: "hidden", name: "_method",            value: "patch")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div(class: "flex flex-col gap-5") do
                # Accepted methods
                div do
                  p(class: "text-[10px] font-bold uppercase tracking-[0.08em] text-gray-500 mb-1.5") do
                    plain "Accepted methods"
                  end
                  p(class: "#{TYPE_CAPTION} mb-3") { plain "At least one must remain enabled." }
                  div(class: "flex flex-col gap-[6px]") do
                    METHODS.each do |m|
                      enabled = methods.include?(m[:value])
                      div(class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] " \
                                 "border border-gray-100 hover:border-gray-200 transition-colors") do
                        input(type:  "checkbox",
                              name:  "allowed_methods[]",
                              value: m[:value],
                              id:    "sm_#{m[:value]}",
                              class: "w-[14px] h-[14px] rounded cursor-pointer flex-shrink-0",
                              style: "accent-color:#{BRAND}",
                              **(enabled ? { checked: true } : {}))
                        div do
                          label(for:   "sm_#{m[:value]}",
                                class: "block text-[13px] font-semibold text-gray-800 cursor-pointer leading-tight") do
                            plain m[:label]
                          end
                          p(class: "text-[11px] text-gray-400 leading-tight mt-[1px]") { plain m[:detail] }
                        end
                      end
                    end
                  end
                end

                # Collect from customer
                div do
                  p(class: "text-[10px] font-bold uppercase tracking-[0.08em] text-gray-500 mb-2") do
                    plain "Collect from customer"
                  end
                  div(class: "flex flex-col gap-[6px]") do
                    [
                      %w[collect_email Email\ address],
                      %w[collect_phone Phone\ number],
                      %w[collect_name  Full\ name]
                    ].each do |name, label_text|
                      div(class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] " \
                                 "border border-gray-100 hover:border-gray-200 transition-colors") do
                        input(type:  "checkbox",
                              name:  name,
                              value: "1",
                              id:    name,
                              class: "w-[14px] h-[14px] rounded cursor-pointer flex-shrink-0",
                              style: "accent-color:#{BRAND}",
                              **(@link[name] ? { checked: true } : {}))
                        label(for:   name,
                              class: "block text-[13px] font-semibold text-gray-800 cursor-pointer leading-tight") do
                          plain label_text
                        end
                      end
                    end
                  end
                end

                # Usage & expiry — reusable links only
                if @link["reusable"]
                  div do
                    p(class: "text-[10px] font-bold uppercase tracking-[0.08em] text-gray-500 mb-3") do
                      plain "Usage & expiry"
                    end
                    div(class: "flex flex-col gap-3") do
                      div do
                        label(class: "block text-[11px] font-semibold text-gray-600 mb-[5px]") do
                          plain "Maximum uses"
                        end
                        input(type:        "number",
                              name:        "max_uses",
                              min:         "1",
                              value:       @link["max_uses"],
                              placeholder: "Unlimited",
                              class:       INPUT_FIELD)
                      end
                      div do
                        label(class: "block text-[11px] font-semibold text-gray-600 mb-[5px]") do
                          plain "Link expiry"
                        end
                        expiry_val = begin
                          @link["expires_at"].present? ? Time.parse(@link["expires_at"]).strftime("%Y-%m-%dT%H:%M") : nil
                        rescue
                          nil
                        end
                        input(type:  "datetime-local",
                              name:  "expires_at",
                              value: expiry_val,
                              class: INPUT_FIELD)
                      end
                    end
                  end
                end

                div(class: "flex justify-end pt-2 border-t border-gray-100") do
                  render UI::Button.new(variant: :primary, type: "submit") { plain "Save settings" }
                end
              end
            end
          end
        end
      end

      # ── Right column (1fr) ────────────────────────────────────────────────────

      def right_column
        div(class: "flex flex-col gap-5") do
          analytics_card
          share_card
          checkout_preview_card
        end
      end

      def analytics_card
        views       = @analytics[:views].to_i
        completions = @analytics[:completions].to_i
        expired     = @analytics[:expired].to_i
        rate        = views > 0 ? (completions * 100.0 / views).round : 0

        render UI::Card.new do |c|
          c.header("Analytics", icon: :chart)
          c.body do
            div(class: "grid grid-cols-3 gap-2 mb-4") do
              analytic_stat("Views",     views.to_s,       "#3D47F5")
              analytic_stat("Completed", completions.to_s, "#16a34a")
              analytic_stat("Expired",   expired.to_s,     "#d97706")
            end

            if views > 0
              div(class: "flex items-center gap-2 mb-1.5") do
                span(class: TYPE_CAPTION) { plain "Conversion rate" }
                span(class: "ml-auto text-[13px] font-bold tabular-nums",
                     style: "color:#{rate >= 50 ? "#16a34a" : rate >= 20 ? "#d97706" : "#dc2626"}") do
                  plain "#{rate}%"
                end
              end
              div(class: "w-full h-1.5 rounded-full overflow-hidden bg-gray-100") do
                div(class: "h-full rounded-full",
                    style: "width:#{rate}%;background:#{rate >= 50 ? "#16a34a" : rate >= 20 ? "#d97706" : "#dc2626"}")
              end
            else
              p(class: "#{TYPE_CAPTION} italic") { plain "Share the link to start seeing activity here." }
            end
          end
        end
      end

      def analytic_stat(label_text, value, color)
        div(class: "flex flex-col items-center gap-[3px] rounded-[10px] py-[10px]",
            style: "background:#{color}0d;border:1px solid #{color}20") do
          span(class: "text-[20px] font-extrabold tabular-nums leading-tight", style: "color:#{color}") do
            plain value
          end
          span(class: "text-[9px] font-bold uppercase tracking-widest text-gray-400") { plain label_text }
        end
      end

      def share_card
        url = @link["checkout_url"].to_s

        render UI::Card.new do |c|
          c.header("Share link", icon: :link)
          c.body(padding: false) do
            div(class: "flex items-center px-4 py-3 gap-0 border-b border-gray-50") do
              a(href: url, target: "_blank", rel: "noopener noreferrer",
                class: "flex-1 min-w-0 font-mono text-[11.5px] text-[#3D47F5] hover:underline truncate") do
                plain url
              end
            end
            div(class: "flex items-center divide-x divide-gray-100") do
              share_action_btn("pl-copy-btn", :copy, "Copy",     data: { url: url })
              a(href:   "https://wa.me/?text=#{CGI.escape("#{@link["description"].presence || "Pay here"}: #{url}")}",
                target: "_blank",
                rel:    "noopener noreferrer",
                class:  share_action_cls + " no-underline") do
                span(class: "text-[13px] leading-none") { plain "💬" }
                plain "WhatsApp"
              end
              share_action_btn("pl-qr-btn", :qr_code, "QR code", data: { url: payment_link_display_path(@link["id"]) })
            end
          end
        end
      end

      def share_action_btn(id, icon, label, data: {})
        button(
          type:  "button",
          id:    id,
          class: share_action_cls,
          data:  data
        ) do
          render UI::Icon.new(icon, class: "w-3.5 h-3.5")
          plain label
        end
      end

      def share_action_cls
        "flex flex-1 items-center justify-center gap-[5px] py-[10px] text-[12px] font-medium " \
          "text-gray-500 hover:bg-gray-50 hover:text-gray-700 transition-colors cursor-pointer border-0 bg-transparent"
      end

      def checkout_preview_card
        sym           = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed         = @link["kind"] == "fixed_amount"
        amt           = @link["amount"].to_i
        methods_list  = Array(@link["allowed_methods"])
        saved_logo    = @link.dig("checkout_layout", "logo_url").to_s
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        initials      = merchant_name.split.first(2).map { |w| w[0].upcase }.join

        render UI::Card.new do |c|
          c.header("Checkout preview", icon: :eye)
          c.body do
            # Brand bar
            div(class: "flex items-center gap-2.5 px-4 py-3 border border-gray-100 rounded-xl mb-4") do
              if saved_logo.present?
                img(src: saved_logo, alt: "Logo",
                    class: "w-6 h-6 rounded-lg object-cover border border-gray-100 flex-shrink-0")
              else
                div(class: "w-6 h-6 rounded-lg bg-[#3D47F5] flex items-center justify-center flex-shrink-0") do
                  span(class: "text-[9px] font-bold text-white") { plain initials }
                end
              end
              p(class: "text-[12px] font-semibold text-gray-700") { plain merchant_name }
              span(class: "ml-auto text-[10px] font-semibold px-[7px] py-[2px] rounded-full bg-gray-100 text-gray-400") do
                plain (@link["mode"] || "simulation").capitalize
              end
            end

            # Amount
            if fixed && amt > 0
              p(class: "text-[9px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1") { plain "Total" }
              p(class: "text-[30px] font-extrabold text-gray-900 leading-none tracking-tight tabular-nums mb-2") do
                span(class: "text-[16px] font-bold text-gray-400 mr-1") { plain sym }
                plain "%.2f" % (amt / 100.0)
              end
              p(class: "text-[13px] font-medium text-gray-500 mb-4") do
                plain @link["description"].presence || "Payment"
              end
            else
              p(class: "text-[9px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "Amount" }
              div(class: "h-10 bg-gray-50 border border-gray-200 rounded-[10px] flex items-center px-3 mb-4") do
                p(class: "text-[12px] text-gray-300") { plain "Enter amount..." }
              end
            end

            div(class: "h-px bg-gray-100 mb-4")

            # Payment methods
            p(class: "text-[9px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "Pay with" }
            div(class: "flex flex-wrap gap-2 mb-5") do
              methods_list.each do |m|
                meta = METHOD_META[m] || { label: m.humanize, icon: "•" }
                div(class: "flex items-center gap-1.5 px-2.5 py-[6px] rounded-[9px] " \
                           "border border-gray-200 text-[11.5px] font-medium text-gray-700") do
                  span(class: "text-[13px]") { plain meta[:icon] }
                  plain meta[:label]
                end
              end
            end

            # Collect fields
            collect_any = @link["collect_email"] || @link["collect_phone"] || @link["collect_name"]
            if collect_any
              div(class: "flex flex-col gap-2.5 mb-5") do
                preview_field("Full name",     "Your name")        if @link["collect_name"]
                preview_field("Email address", "you@example.com")  if @link["collect_email"]
                preview_field("Phone number",  "+233 24 000 0000") if @link["collect_phone"]
              end
            end

            # Pay button
            pay_label = fixed && amt > 0 ? "Pay #{sym}#{"%.2f" % (amt / 100.0)}" : "Pay now"
            div(class: "w-full py-3.5 rounded-[10px] bg-[#3D47F5] flex items-center justify-center " \
                       "text-[13.5px] font-bold text-white cursor-default select-none") do
              plain pay_label
            end

            div(class: "flex items-center justify-center gap-[5px] mt-3") do
              span(class: "text-[10px] text-gray-300") { plain "Powered by" }
              span(class: "text-[10px] font-bold text-[#3D47F5]/60") { plain "Yagye" }
            end
          end
        end
      end

      def preview_field(label_text, placeholder)
        div do
          p(class: "text-[9px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") { plain label_text }
          div(class: "w-full h-[38px] border border-gray-200 rounded-[10px] px-3 flex items-center " \
                     "text-[12.5px] text-gray-300") { plain placeholder }
        end
      end

      # ── Copy / QR script ──────────────────────────────────────────────────────

      def copy_script(url)
        script do
          raw safe(<<~JS)
            (function () {
              var copyBtn = document.getElementById('pl-copy-btn');
              if (copyBtn) {
                copyBtn.addEventListener('click', function () {
                  navigator.clipboard.writeText(#{url.to_json}).then(function () {
                    copyBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>Copied!</span>';
                    copyBtn.style.color = '#16a34a';
                    setTimeout(function () {
                      copyBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg><span>Copy</span>';
                      copyBtn.style.color = '';
                    }, 2000);
                  }).catch(function () {
                    copyBtn.textContent = 'Copy link';
                  });
                });
              }
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
    end
  end
end
