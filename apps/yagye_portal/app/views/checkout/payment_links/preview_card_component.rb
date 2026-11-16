# frozen_string_literal: true

module Checkout
  module PaymentLinks
    class PreviewCardComponent < ApplicationComponent
      include UI::Theme

      ICON_PHONE = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg>'
      ICON_CARD  = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="4" width="22" height="16" rx="2" ry="2"/><line x1="1" y1="10" x2="23" y2="10"/></svg>'
      ICON_BANK  = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="22" x2="21" y2="22"/><line x1="6" y1="18" x2="6" y2="11"/><line x1="10" y1="18" x2="10" y2="11"/><line x1="14" y1="18" x2="14" y2="11"/><line x1="18" y1="18" x2="18" y2="11"/><polygon points="12 2 20 7 4 7"/></svg>'
      SVG_VISA   = '<svg width="34" height="22" viewBox="0 0 40 26" xmlns="http://www.w3.org/2000/svg"><rect width="40" height="26" rx="4" fill="#1A1F71"/><text x="20" y="18" font-family="Inter,sans-serif" font-size="11" font-weight="900" fill="#FFF" text-anchor="middle" letter-spacing="1">VISA</text></svg>'
      SVG_MC     = '<svg width="34" height="22" viewBox="0 0 40 26" xmlns="http://www.w3.org/2000/svg"><rect width="40" height="26" rx="4" fill="#1D1D1B"/><circle cx="15" cy="13" r="7.5" fill="#EB001B"/><circle cx="25" cy="13" r="7.5" fill="#F79E1B"/><path d="M20 7.8a7.5 7.5 0 010 10.4A7.5 7.5 0 0120 7.8z" fill="#FF5F00"/></svg>'
      SVG_VERVE  = '<svg width="34" height="22" viewBox="0 0 40 26" xmlns="http://www.w3.org/2000/svg"><rect width="40" height="26" rx="4" fill="#E31837"/><text x="20" y="17" font-family="Inter,sans-serif" font-size="10" font-weight="700" fill="#FFF" text-anchor="middle">verve</text></svg>'

      METHODS_CONFIG = [
        { value: "mobile_money",  label: "Mobile Money",  icon: ICON_PHONE },
        { value: "card",          label: "Card",          icon: ICON_CARD  },
        { value: "bank_transfer", label: "Bank Transfer", icon: ICON_BANK  }
      ].freeze

      def initialize(brand_color:, merchant_name:, amount_display:, description:,
                     allowed_methods:, collect_email: false, collect_phone: false,
                     collect_name: false, cta_text: nil, escrow_enabled: false,
                     logo_url: nil, mode: nil, show_label: true,
                     headline: nil, terms: nil)
        @bc               = brand_color.to_s.presence || "#3D47F5"
        @merchant_name    = merchant_name.to_s
        @merchant_initials = @merchant_name.split.first(2).map { |w| w[0]&.upcase || "" }.join.presence || "Y"
        @amount_display   = amount_display.to_s.presence || "You choose"
        @description      = description.to_s.presence || "Your product"
        @allowed_methods  = Array(allowed_methods).map(&:to_s)
        @collect_email    = collect_email
        @collect_phone    = collect_phone
        @collect_name     = collect_name
        @cta_text         = cta_text.to_s.presence
        @escrow_enabled   = escrow_enabled
        @logo_url         = logo_url.to_s.presence
        @mode             = mode
        @show_label       = show_label
        @headline         = headline.to_s.presence
        @terms            = terms  # nil or { label:, url: }
      end

      def view_template
        div(class: "w-full max-w-[900px]") do
          if @show_label
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.15em] text-gray-400 text-center mb-4") do
              plain "Customer sees"
            end
          end

          div(
            class: "bg-white rounded-2xl overflow-hidden border border-gray-200/60 " \
                   "shadow-[0_16px_56px_rgba(0,0,0,0.10),0_2px_12px_rgba(0,0,0,0.06)]",
            data:  { "pv-preview-card": true }
          ) do
            browser_chrome
            div(class: "grid grid-cols-2", style: "min-height:480px") do
              left_panel
              right_panel
            end
          end
        end
      end

      private

      def browser_chrome
        div(class: "flex items-center gap-3 px-4 py-[10px] bg-[#F3F4F6] border-b border-gray-200") do
          div(class: "flex items-center gap-[5px] flex-shrink-0") do
            div(class: "w-3 h-3 rounded-full bg-[#FF5F57]")
            div(class: "w-3 h-3 rounded-full bg-[#FEBC2E]")
            div(class: "w-3 h-3 rounded-full bg-[#28C840]")
          end
          div(class: "flex-1 mx-4 bg-white border border-gray-200/80 rounded-lg px-3 py-[5px] " \
                     "flex items-center gap-1.5") do
            span(class: "text-[9px] text-gray-400") { plain "🔒" }
            span(class: "text-[11px] text-gray-500 font-medium") { plain "checkout.yagye.io" }
          end
          div(class: "w-[52px] flex-shrink-0")
        end
      end

      def left_panel
        div(class: "flex flex-col px-10 py-8", style: "background:#F9FAFB") do
          div(class: "flex items-center gap-2 text-gray-400 mb-6") do
            span(class: "text-[11px] font-medium cursor-default select-none") { plain "✕" }
            div(class: "w-px h-3 bg-gray-300 mx-0.5")
            span(class: "text-[11px] font-semibold text-gray-700") { plain "Checkout" }
          end

          div(class: "flex items-center gap-2.5 mb-7") do
            if @logo_url
              img(src: @logo_url, alt: "Logo",
                  style: "width:36px;height:36px;border-radius:10px;object-fit:cover;flex-shrink:0;")
            else
              div(
                class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
                style: "background:#{@bc}",
                data:  { "pv-brand-bg": true }
              ) do
                span(
                  class: "text-[12px] font-bold text-white",
                  data:  { "pv-merchant-initials": true }
                ) { plain @merchant_initials }
              end
            end
            div do
              p(
                class: "text-[13px] font-semibold text-gray-900 leading-tight",
                data:  { "pv-merchant-name": true }
              ) { plain @merchant_name }
              span(
                class: "inline-block text-[9px] font-semibold rounded-full px-[6px] py-[1px] mt-[2px] " \
                       "bg-emerald-50 text-emerald-600 border border-emerald-100"
              ) { plain "Verified merchant" }
            end
          end

          p(class: "text-[9px] font-bold uppercase tracking-[0.18em] text-gray-400 mb-1") { plain "PAY" }
          p(
            class: "text-[36px] font-extrabold text-gray-900 leading-none tracking-tight tabular-nums mb-3",
            data:  { payment_link_compose_target: "pvAmount" }
          ) { plain @amount_display }

          p(
            class: "text-[13px] text-gray-500 mb-6",
            data:  { payment_link_compose_target: "pvDescription" }
          ) { plain @description }

          div(hidden: !@headline, data: { "pv-headline-wrapper": true }) do
            p(class: "text-[12px] font-semibold text-gray-700 leading-snug -mt-2 mb-4",
              data:  { "pv-headline": true }) { plain @headline.to_s }
          end

          div(class: "h-px bg-gray-200 mb-4")

          div(class: "flex items-center justify-between") do
            span(class: "text-[12px] font-semibold text-gray-700") { plain "Total due" }
            span(
              class: "text-[13px] font-bold text-gray-900 tabular-nums",
              data:  { payment_link_compose_target: "pvAmountLabel" }
            ) { plain @amount_display }
          end
        end
      end

      def right_panel
        div(
          class: "flex flex-col px-8 py-8 border-l border-gray-100",
          style: "background:#FFFFFF"
        ) do
          any_collect = @collect_email || @collect_phone || @collect_name

          div(
            class:  "mb-5",
            hidden: !any_collect,
            data:   { payment_link_compose_target: "pvCustomerSection" }
          ) do
            p(class: "text-[9px] font-bold uppercase tracking-[0.14em] text-gray-400 mb-3") do
              plain "Contact information"
            end
            div(class: "flex flex-col gap-2") do
              collect_field("email", "you@example.com", "✉️", visible: @collect_email)
              collect_field("phone", "+233 24 000 0000", "📱", visible: @collect_phone)
              collect_field("name",  "Your name",        "👤", visible: @collect_name)
            end
          end

          p(class: "text-[9px] font-bold uppercase tracking-[0.14em] text-gray-400 mb-3") do
            plain "Payment method"
          end

          first_enabled_found = false
          div(class: "flex flex-col border border-[#E5E7EB] rounded-[12px] overflow-hidden mb-5",
              data:  { "pv-method-list": true }) do
            METHODS_CONFIG.each_with_index do |m, i|
              enabled  = @allowed_methods.include?(m[:value])
              selected = enabled && !first_enabled_found
              first_enabled_found = true if selected
              body_lam = case m[:value]
              when "mobile_money"  then -> { mobile_money_preview_body }
              when "card"          then -> { card_preview_body }
              when "bank_transfer" then -> { bank_transfer_preview_body }
              end
              preview_method_item(
                m[:value], m[:label], m[:icon],
                selected: selected,
                hidden:   !enabled,
                first:    i == 0,
                body:     body_lam
              ) { logos_for(m[:value]) }
            end
          end

          div(hidden: !@terms, data: { "pv-terms-row": true }) do
            div(class: "flex items-start gap-[8px] px-3 py-[9px] mb-3 bg-gray-50 rounded-xl border border-gray-100") do
              div(class: "w-[13px] h-[13px] mt-[1px] rounded-[3px] border-[2px] flex-shrink-0",
                  style: "border-color:#{@bc}") { }
              span(class: "text-[11px] leading-snug flex-1 text-gray-500",
                   data:  { "pv-terms-label": true }) do
                plain @terms&.dig(:label) || "I agree to the Terms & Conditions"
              end
            end
          end

          div(class: "flex-1")

          cta = @cta_text || "Pay #{@amount_display}"
          div(
            class: "w-full py-[14px] rounded-[11px] flex items-center justify-center " \
                   "text-[13.5px] font-bold text-white cursor-default select-none mb-3",
            style: "background:#{@bc}",
            data:  { payment_link_compose_target: "pvPayButton", "pv-brand-bg": true }
          ) { plain cta }

          div(class: "flex items-center justify-center gap-1.5 mb-2") do
            span(class: "text-[10px] text-gray-400") { plain "🔒" }
            span(class: "text-[10px] text-gray-400") { plain "Secure & encrypted payment" }
          end

          div(
            class:  "flex items-center justify-center gap-[5px] mb-2",
            hidden: !@escrow_enabled,
            data:   { payment_link_compose_target: "pvEscrowBadge" }
          ) do
            span(class: "text-[10px]") { plain "🔒" }
            span(class: "text-[10px] font-semibold text-amber-600") do
              plain "Payment held in trust until receipt confirmed"
            end
          end

          div(class: "flex items-center justify-center gap-[5px] mt-1") do
            span(class: "text-[10px] text-gray-300") { plain "Powered by" }
            span(class: "text-[10px] font-bold", style: "color:#{@bc};opacity:0.55") { plain "Yagye" }
            span(class: "text-[10px] text-gray-200 mx-1") { plain "·" }
            span(class: "text-[10px] text-gray-300") { plain "Terms" }
            span(class: "text-[10px] text-gray-200 mx-1") { plain "·" }
            span(class: "text-[10px] text-gray-300") { plain "Privacy" }
          end
        end
      end

      def collect_field(type, placeholder, icon, visible:)
        div(hidden: !visible, data: { "pl-collect": "collect_#{type}" }) do
          div(class: "w-full h-[40px] border border-gray-200 rounded-[10px] px-3 flex items-center gap-2 bg-white") do
            span(class: "text-[11px] text-gray-400 flex-shrink-0 leading-none") { plain icon }
            span(class: "text-[12px] text-gray-300") { plain placeholder }
          end
        end
      end

      def logos_for(value)
        case value
        when "mobile_money"
          img(src: asset_path("momo.png"),    width: 20, height: 20, alt: "MTN",     style: "border-radius:4px;object-fit:cover;display:block;")
          img(src: asset_path("telecel.png"), width: 20, height: 20, alt: "Telecel", style: "border-radius:4px;object-fit:cover;display:block;")
          img(src: asset_path("at.png"),      width: 20, height: 20, alt: "AT",      style: "border-radius:4px;object-fit:cover;display:block;")
        when "card"
          raw safe(SVG_VISA)
          raw safe(SVG_MC)
          raw safe(SVG_VERVE)
        when "bank_transfer"
          span(style: "font-size:10.5px;color:#6B7280;font-weight:500;") { plain "GhIPSS" }
        end
      end

      def preview_method_item(value, label, icon_svg, selected:, hidden: false, first: false, body: nil, &logos)
        div(
          class:  "pv-method-item overflow-hidden",
          hidden: hidden,
          data:   { "pl-method": value, action: "click->payment-link-compose#selectPreviewMethod" }
        ) do
          div(class: "pv-method-sep h-px bg-[#E5E7EB]") unless first
          div(
            class: "pv-method-hd flex items-center gap-[11px] px-[14px] py-[13px] cursor-pointer transition-colors",
            style: selected ? "background:#{@bc}0d" : "background:#FFFFFF"
          ) do
            div(
              class: "pv-radio-dot flex-shrink-0 flex items-center justify-center",
              style: "width:17px;height:17px;border-radius:50%;border:2px solid #{selected ? @bc : '#E5E7EB'};transition:border-color 0.14s"
            ) do
              div(
                class: "pv-radio-inner",
                hidden: !selected,
                style: "width:8px;height:8px;border-radius:50%;background:#{@bc}"
              )
            end
            span(
              class: "pv-method-icon flex-shrink-0 flex items-center justify-center",
              style: "width:22px;height:22px;color:#{selected ? @bc : '#9CA3AF'}"
            ) { raw safe(icon_svg) }
            p(
              class: "flex-1 text-[13px] leading-tight",
              style: selected ? "font-weight:600;color:#111827" : "font-weight:500;color:#6B7280"
            ) { plain label }
            div(class: "flex items-center gap-[3px] flex-shrink-0") { logos.call }
          end
          if body
            div(
              class: "px-[14px] pb-[14px]",
              hidden: !selected,
              data:  { "pl-method-body": true }
            ) { instance_exec(&body) }
          end
        end
      end

      def mobile_money_preview_body
        bc = @bc
        div(class: "mb-[14px]") do
          p(style: "font-size:10px;font-weight:600;color:#9CA3AF;text-transform:uppercase;letter-spacing:0.18em;display:block;margin-bottom:6px;") { plain "Network" }
          div(style: "display:grid;grid-template-columns:repeat(3,1fr);gap:6px;") do
            [
              [ asset_path("momo.png"),    "MTN",        true ],
              [ asset_path("telecel.png"), "Telecel",    false ],
              [ asset_path("at.png"),      "AirtelTigo", false ]
            ].each do |logo, name, active|
              div(
                style: [
                  "display:flex;flex-direction:column;align-items:center;gap:5px;",
                  "padding:10px 6px 8px;border-radius:10px;border:1px solid;cursor:default;",
                  active ? "border-color:#{bc};color:#{bc};font-weight:600;" : "border-color:#E5E7EB;color:#9CA3AF;font-weight:500;"
                ].join
              ) do
                div(style: "width:32px;height:32px;border-radius:7px;overflow:hidden;flex-shrink:0;") do
                  img(src: logo, width: 32, height: 32, style: "object-fit:cover;display:block;")
                end
                span(style: "font-size:11px;line-height:1.1;white-space:nowrap;color:inherit;") { plain name }
              end
            end
          end
        end
        div do
          p(style: "font-size:10px;font-weight:600;color:#9CA3AF;text-transform:uppercase;letter-spacing:0.18em;display:block;margin-bottom:6px;") { plain "Mobile Money number" }
          div(style: "display:flex;align-items:center;border:1px solid #E5E7EB;border-radius:12px;overflow:hidden;") do
            div(style: "display:flex;align-items:center;gap:5px;padding:11px 12px;font-size:14px;font-weight:500;color:#374151;border-right:1px solid #E5E7EB;background:#F9FAFB;flex-shrink:0;white-space:nowrap;") do
              plain "🇬🇭"
              span(style: "font-size:14px;font-weight:500;color:#374151;") { plain "+233" }
            end
            div(style: "flex:1;padding:11px 12px;font-size:14px;color:#D1D5DB;") { plain "024 000 0000" }
          end
        end
      end

      def card_preview_body
        div(style: "margin-bottom:14px;") do
          p(style: "font-size:10px;font-weight:600;color:#9CA3AF;text-transform:uppercase;letter-spacing:0.18em;display:block;margin-bottom:6px;") { plain "Card number" }
          div(style: "display:flex;align-items:center;border:1px solid #E5E7EB;border-radius:12px;overflow:hidden;") do
            div(style: "flex:1;padding:12px 16px;font-size:14px;color:#D1D5DB;letter-spacing:0.08em;") { plain "0000  0000  0000  0000" }
          end
        end
        div(style: "display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:14px;") do
          div do
            p(style: "font-size:10px;font-weight:600;color:#9CA3AF;text-transform:uppercase;letter-spacing:0.18em;display:block;margin-bottom:6px;") { plain "Expiry" }
            div(style: "padding:12px 16px;border:1px solid #E5E7EB;border-radius:12px;font-size:14px;color:#D1D5DB;") { plain "MM/YY" }
          end
          div do
            p(style: "font-size:10px;font-weight:600;color:#9CA3AF;text-transform:uppercase;letter-spacing:0.18em;display:block;margin-bottom:6px;") { plain "CVV" }
            div(style: "padding:12px 16px;border:1px solid #E5E7EB;border-radius:12px;font-size:14px;color:#D1D5DB;") { plain "•••" }
          end
        end
        div do
          p(style: "font-size:10px;font-weight:600;color:#9CA3AF;text-transform:uppercase;letter-spacing:0.18em;display:block;margin-bottom:6px;") { plain "Name on card" }
          div(style: "padding:12px 16px;border:1px solid #E5E7EB;border-radius:12px;font-size:14px;color:#D1D5DB;letter-spacing:0.04em;") { plain "JOHN DOE" }
        end
      end

      def bank_transfer_preview_body
        div(style: "display:flex;align-items:flex-start;gap:8px;padding:10px 12px;border-radius:10px;background:rgba(59,130,246,0.05);border:1px solid rgba(59,130,246,0.15);color:#1D4ED8;font-size:12px;line-height:1.5;") do
          raw safe('<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;margin-top:1px"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>')
          div do
            p(style: "font-weight:600;margin-bottom:2px;") { plain "Unique account generated per payment" }
            p(style: "font-size:12px;color:#1D4ED8;line-height:1.5;") do
              plain "Click Pay to generate a dedicated bank account for this transaction. Transfer the exact amount via "
              span(style: "font-weight:700;color:#1e40af;") { plain "GhIPSS Instant Pay" }
              plain " — your payment is confirmed automatically in seconds."
            end
          end
        end
      end
    end
  end
end
