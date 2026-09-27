# frozen_string_literal: true

module Checkout
  module PaymentLinks
    class DisplayView < ApplicationComponent
      include UI::Theme

      CURRENCY_SYMBOLS = { "GHS" => "GH₵", "NGN" => "₦", "KES" => "KSh", "XOF" => "CFA", "USD" => "$" }.freeze

      def initialize(link:)
        @link = link
      end

      def view_template
        print_styles

        div(class: "min-h-screen flex flex-col items-center justify-center p-6 no-print-bg",
            style: "background:#f2f3f7") do
          # Back link — hidden on print
          div(class: "w-full max-w-sm mb-3 flex items-center justify-between no-print") do
            a(id:   "pl-back-btn",
              href: payment_link_path(@link["id"]),
              class: "flex items-center gap-[5px] text-[12px] font-medium text-gray-400 " \
                     "hover:text-gray-700 transition-colors no-underline") do
              span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:chev_left, class: "w-full h-full") }
              plain "Back to portal"
            end
            span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-200/70 text-gray-500") do
              plain (@link["mode"] || "simulation").capitalize
            end
          end

          # Main card
          div(id: "display-card",
              class: "bg-white rounded-3xl w-full max-w-sm overflow-hidden " \
                     "shadow-[0_24px_64px_rgba(0,0,0,0.12),0_4px_16px_rgba(0,0,0,0.06)]") do
            merchant_header
            qr_section
            amount_section
            action_bar
          end

          # Hint — hidden on print
          p(class: "mt-4 text-[11px] text-gray-400 text-center no-print") do
            plain "Customers scan this code to open your payment page"
          end
        end

        qr_script
      end

      private

      def print_styles
        style do
          raw safe(%(
            @media print {
              @page {
                margin: 0;
                size: A5 portrait;
              }
              body {
                background: white !important;
                padding: 1cm !important;
                margin: 0 !important;
              }
              .no-print { display: none !important; }
              .no-print-bg {
                background: white !important;
                padding: 0 !important;
                min-height: auto !important;
                justify-content: flex-start !important;
              }
              #display-card {
                box-shadow: none !important;
                border-radius: 16px !important;
                border: 1px solid #e5e7eb !important;
                width: 100% !important;
                max-width: 100% !important;
              }
            }
          ))
        end
      end

      def merchant_header
        saved_logo    = @link.dig("checkout_layout", "logo_url").to_s
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        initials      = merchant_name.split.first(2).map { |w| w[0].upcase }.join

        div(class: "flex flex-col items-center gap-[10px] px-8 pt-8 pb-5") do
          if saved_logo.present?
            img(src: saved_logo, alt: "Logo",
                class: "w-16 h-16 rounded-2xl object-cover border border-gray-100 shadow-sm flex-shrink-0")
          else
            div(class: "w-16 h-16 rounded-2xl bg-[#3D47F5] flex items-center justify-center flex-shrink-0 " \
                       "shadow-[0_4px_12px_rgba(61,71,245,0.3)]") do
              span(class: "text-[20px] font-bold text-white") { plain initials }
            end
          end

          div(class: "text-center") do
            p(class: "text-[16px] font-bold text-gray-900 leading-tight") { plain merchant_name }
            if @link["description"].present?
              p(class: "text-[13px] text-gray-500 mt-[3px] leading-snug") { plain @link["description"] }
            end
          end
        end

        div(class: "h-px bg-gray-100 mx-5")
      end

      def qr_section
        url = @link["checkout_url"].to_s

        div(class: "flex flex-col items-center gap-4 px-8 pt-7 pb-5") do
          div(
            id:    "pl-display-qr",
            class: "rounded-2xl overflow-hidden border border-gray-100 bg-gray-50 " \
                   "flex items-center justify-center",
            style: "width:240px;height:240px"
          ) do
            span(class: "text-[12px] text-gray-400") { plain "Generating…" }
          end

          p(class: "text-[11px] font-mono text-gray-400 text-center break-all leading-relaxed px-2") do
            plain url
          end
        end

        div(class: "h-px bg-gray-100 mx-5")
      end

      def amount_section
        sym   = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed = @link["kind"] == "fixed_amount"
        amt   = @link["amount"].to_i

        div(class: "flex items-center justify-center gap-3 px-8 py-5") do
          if fixed && amt > 0
            div(class: "flex flex-col items-center gap-[6px]") do
              p(class: "text-[36px] font-extrabold text-gray-900 tabular-nums leading-none tracking-tight") do
                span(class: "text-[20px] font-bold text-gray-400 mr-1") { plain sym }
                plain "%.2f" % (amt / 100.0)
              end
              p(class: "text-[11px] text-gray-400") { plain "Scan to pay this amount" }
            end
          else
            div(class: "flex flex-col items-center gap-[6px]") do
              p(class: "text-[15px] font-semibold text-gray-700") { plain "Scan to pay" }
              p(class: "text-[12px] text-gray-400") { plain "Amount entered at checkout" }
            end
          end
        end

        div(class: "h-px bg-gray-100 mx-5")
      end

      def action_bar
        div(class: "flex items-center gap-3 px-6 py-4 no-print") do
          button(
            type:  "button",
            id:    "pl-print-btn",
            class: "flex-1 flex items-center justify-center gap-[6px] py-[9px] rounded-[10px] " \
                   "bg-[#3D47F5] hover:bg-[#2e38d4] text-white text-[12.5px] font-semibold " \
                   "transition-colors cursor-pointer border-0"
          ) do
            render UI::Icon.new(:printer, class: "w-3.5 h-3.5")
            plain "Print"
          end

          a(
            id:    "pl-display-download",
            href:  "#",
            class: "flex-1 flex items-center justify-center gap-[6px] py-[9px] rounded-[10px] " \
                   "border border-gray-200 text-gray-600 hover:bg-gray-50 text-[12.5px] font-semibold " \
                   "transition-colors no-underline"
          ) do
            render UI::Icon.new(:download, class: "w-3.5 h-3.5 text-gray-400")
            plain "Save PNG"
          end
        end
      end

      def qr_script
        url = @link["checkout_url"].to_s
        script(src: "https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js")
        script do
          raw safe(<<~JS)
            (function () {
              var el = document.getElementById('pl-display-qr');
              var dl = document.getElementById('pl-display-download');
              if (!el) return;
              el.innerHTML = '';
              try {
                new QRCode(el, {
                  text:         #{url.to_json},
                  width:        240,
                  height:       240,
                  correctLevel: QRCode.CorrectLevel.H
                });
                setTimeout(function () {
                  var canvas = el.querySelector('canvas');
                  if (canvas && dl) {
                    dl.href     = canvas.toDataURL('image/png');
                    dl.download = 'payment-qr-#{@link["id"]}.png';
                  }
                }, 300);
              } catch (e) {
                el.innerHTML = '<span style="font-size:12px;color:#9ca3af">QR unavailable</span>';
              }

              document.getElementById('pl-print-btn')?.addEventListener('click', function () {
                window.print();
              });

              // If this tab was opened by the portal, close it on "back" — don't navigate
              var backBtn = document.getElementById('pl-back-btn');
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
    end
  end
end
