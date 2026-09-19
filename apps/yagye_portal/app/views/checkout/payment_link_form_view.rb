# frozen_string_literal: true

module Checkout
  class PaymentLinkFormView < ApplicationComponent
    include UI::Theme

    CURRENCIES = [
      { code: "GHS", label: "GHS — Ghana Cedi",      symbol: "GH₵" },
      { code: "NGN", label: "NGN — Nigerian Naira",   symbol: "₦" },
      { code: "KES", label: "KES — Kenyan Shilling",  symbol: "KSh" },
      { code: "XOF", label: "XOF — West African CFA", symbol: "CFA" },
      { code: "USD", label: "USD — US Dollar",        symbol: "$" }
    ].freeze

    METHODS = [
      { value: "mobile_money",  label: "Mobile Money",  detail: "MTN MoMo, Telecel, AirtelTigo",  icon: "📱" },
      { value: "card",          label: "Card",           detail: "Visa and Mastercard",             icon: "💳" },
      { value: "bank_transfer", label: "Bank transfer",  detail: "Direct bank-to-bank",             icon: "🏦" }
    ].freeze

    def initialize(errors: [], mode: "test")
      @errors = errors
      @mode   = mode
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payment_links,
        title:      "New payment link",
        breadcrumbs: [
          { label: "Payment Links", href: payment_links_path },
          { label: "New" }
        ],
        padded: false
      ) do
        canvas_styles

        div(
          class: "relative h-full overflow-hidden",
          data:  { controller: "payment-link-compose" }
        ) do
          div(id: "pl-canvas", class: "absolute inset-0")
          floating_toolbar
          form(
            id:     "pl-form",
            action: payment_links_path,
            method: "post",
            class:  "absolute top-[76px] left-0 right-0 bottom-0"
          ) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            editor_panel
            preview_area
          end
        end
      end
    end

    private

    # ── Canvas dot grid ──────────────────────────────────────────────────────

    def canvas_styles
      style do
        raw safe(%(
          #pl-canvas {
            background-color: #f8fafc;
            background-image: radial-gradient(circle, #d1d5db 1px, transparent 1px);
            background-size: 24px 24px;
          }
        ))
      end
    end

    # ── Floating toolbar ─────────────────────────────────────────────────────

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
        p(class: "text-[13.5px] font-semibold text-gray-900 px-1") { plain "New payment link" }

        span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500") do
          plain @mode.capitalize
        end

        div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

        if @errors.any?
          span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-red-50 text-red-600") do
            plain "#{@errors.size} error#{"s" if @errors.size > 1}"
          end
        end

        button(
          type:  "submit",
          form:  "pl-form",
          class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                 "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0"
        ) { plain "Create & configure layout" }
      end
    end

    # ── Left editor panel ────────────────────────────────────────────────────

    def editor_panel
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
          link_details_section
          section_divider
          payment_methods_section
          section_divider
          collect_section
          section_divider
          usage_section
        end
      end
    end

    def section_divider
      div(class: "h-px bg-gray-100 mx-3")
    end

    # ── Link details ──────────────────────────────────────────────────────────

    def link_details_section
      div(class: "px-4 pt-3 pb-4") do
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Link details" }
        div(class: "flex flex-col gap-2.5") do
          # Description
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Description" }
            input(
              type:        "text",
              name:        "description",
              placeholder: "e.g. Product deposit, event ticket",
              class:       panel_input_cls,
              required:    true,
              data:        { action: "input->payment-link-compose#syncPreview" }
            )
          end

          # Kind — radio cards
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Payment type" }
            div(class: "grid grid-cols-2 gap-1.5") do
              kind_card("fixed_amount",      "Fixed",      "Set amount",         checked: true)
              kind_card("customer_specified", "Open",       "Customer enters")
            end
          end

          # Amount (shown for fixed only)
          div(data: { payment_link_compose_target: "amountRow" }) do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Amount" }
            input(
              type:        "number",
              name:        "amount",
              step:        "0.01",
              min:         "0.01",
              value:       "50.00",
              placeholder: "0.00",
              class:       "#{panel_input_cls} tabular-nums text-right",
              data:        { action: "input->payment-link-compose#syncPreview" }
            )
          end

          # Currency
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Currency" }
            select(
              name:  "currency",
              class: "#{panel_input_cls} appearance-none cursor-pointer",
              data:  { action: "change->payment-link-compose#syncPreview" }
            ) do
              CURRENCIES.each do |c|
                option(value: c[:code], selected: c[:code] == "GHS") { plain c[:label] }
              end
            end
          end
        end
      end
    end

    def kind_card(value, label, detail, checked: false)
      div(class: "relative cursor-pointer") do
        input(
          type:    "radio",
          name:    "kind",
          value:   value,
          id:      "kind_#{value}",
          class:   "peer sr-only",
          checked: checked || nil,
          data:    { action: "change->payment-link-compose#syncPreview" }
        )
        label(
          for:   "kind_#{value}",
          class: "block cursor-pointer border border-gray-200 rounded-[10px] px-3 py-2.5 " \
                 "peer-checked:border-[#3D47F5] peer-checked:bg-[#3D47F5]/[0.04] transition-colors"
        ) do
          p(class: "text-[12px] font-semibold text-gray-800 leading-tight") { plain label }
          p(class: "text-[10.5px] text-gray-400 mt-[1px] leading-tight") { plain detail }
        end
      end
    end

    # ── Payment methods ───────────────────────────────────────────────────────

    def payment_methods_section
      div(class: "px-4 pt-3 pb-4") do
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-[6px]") { plain "Payment methods" }
        p(class: "text-[10.5px] text-gray-400 mb-3 leading-snug") do
          plain "Choose at least one method for the checkout page."
        end
        div(class: "flex flex-col gap-[6px]") do
          METHODS.each do |m|
            method_toggle(m[:value], m[:label], m[:detail])
          end
        end
      end
    end

    def method_toggle(value, label_text, detail)
      div(class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] border border-gray-100 " \
                 "hover:border-gray-200 transition-colors") do
        input(
          type:  "checkbox",
          name:  "allowed_methods[]",
          value: value,
          id:    "method_#{value}",
          class: "w-[14px] h-[14px] rounded flex-shrink-0 accent-[#3D47F5] cursor-pointer",
          checked: true,
          data:  { action: "change->payment-link-compose#syncPreview" }
        )
        div do
          label(for: "method_#{value}",
                class: "block text-[12px] font-semibold text-gray-800 cursor-pointer leading-tight") do
            plain label_text
          end
          p(class: "text-[10.5px] text-gray-400 leading-tight") { plain detail }
        end
      end
    end

    # ── Collect from customer ─────────────────────────────────────────────────

    def collect_section
      div(class: "px-4 pt-3 pb-4") do
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-[6px]") { plain "Collect from customer" }
        p(class: "text-[10.5px] text-gray-400 mb-3 leading-snug") do
          plain "Optional fields shown on the checkout page."
        end
        div(class: "flex flex-col gap-[6px]") do
          collect_toggle("collect_email", "Email address")
          collect_toggle("collect_phone", "Phone number")
          collect_toggle("collect_name",  "Full name")
        end
      end
    end

    def collect_toggle(name, label_text)
      div(class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] border border-gray-100 " \
                 "hover:border-gray-200 transition-colors") do
        input(
          type:  "checkbox",
          name:  name,
          value: "1",
          id:    name,
          class: "w-[14px] h-[14px] rounded flex-shrink-0 accent-[#3D47F5] cursor-pointer",
          data:  { action: "change->payment-link-compose#syncPreview" }
        )
        label(for: name,
              class: "block text-[12px] font-semibold text-gray-800 cursor-pointer leading-tight") do
          plain label_text
        end
      end
    end

    # ── Usage ─────────────────────────────────────────────────────────────────

    def usage_section
      div(class: "px-4 pt-3 pb-5") do
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Usage & expiry" }
        div(class: "flex flex-col gap-2.5") do
          # Reusable toggle
          div(class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] border border-gray-100 " \
                     "hover:border-gray-200 transition-colors") do
            input(
              type:  "checkbox",
              name:  "reusable",
              value: "1",
              id:    "reusable",
              class: "w-[14px] h-[14px] rounded flex-shrink-0 accent-[#3D47F5] cursor-pointer",
              checked: true,
              data:  { action: "change->payment-link-compose#syncPreview" }
            )
            div do
              label(for: "reusable",
                    class: "block text-[12px] font-semibold text-gray-800 cursor-pointer leading-tight") do
                plain "Allow multiple uses"
              end
              p(class: "text-[10.5px] text-gray-400") { plain "Uncheck for single-use" }
            end
          end

          # Max uses (shown when reusable)
          div(data: { payment_link_compose_target: "maxUsesRow" }) do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
              plain "Maximum uses"
            end
            input(
              type:        "number",
              name:        "max_uses",
              min:         "1",
              placeholder: "Leave blank for unlimited",
              class:       "#{panel_input_cls} tabular-nums"
            )
            p(class: "text-[10.5px] text-gray-400 mt-[5px]") { plain "Blank = no limit" }
          end

          # Expiry
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
              plain "Link expiry"
            end
            input(
              type:  "datetime-local",
              name:  "expires_at",
              class: panel_input_cls
            )
            p(class: "text-[10.5px] text-gray-400 mt-[5px]") { plain "Optional — link stops working after this date." }
          end
        end
      end
    end

    # ── Preview area (right) ─────────────────────────────────────────────────

    def preview_area
      div(
        class: "absolute top-5 right-0 bottom-0 flex flex-col items-center " \
               "justify-start pt-0 pb-8 overflow-y-auto",
        style: "left: 385px"
      ) do
        checkout_preview_card
      end
    end

    def checkout_preview_card
      div(class: "w-full max-w-[420px]") do
        # Preview label
        p(class: "text-[9.5px] font-bold uppercase tracking-[0.15em] text-gray-400 text-center mb-4") do
          plain "Customer sees"
        end

        div(
          class: "bg-white rounded-2xl overflow-hidden " \
                 "shadow-[0_12px_40px_rgba(0,0,0,0.10),0_2px_10px_rgba(0,0,0,0.05)]"
        ) do
          # Brand bar
          div(class: "flex items-center gap-2.5 px-6 py-4 border-b border-gray-50") do
            div(class: "w-7 h-7 rounded-lg bg-[#3D47F5] flex items-center justify-center flex-shrink-0") do
              span(class: "text-[10px] font-bold text-white") { plain "YB" }
            end
            p(class: "text-[12.5px] font-semibold text-gray-700") { plain "Your business" }
          end

          # Amount + description
          div(class: "px-6 pt-6 pb-5") do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1",
              data: { payment_link_compose_target: "pvAmountLabel" }) { plain "Total" }
            p(class: "text-[30px] font-extrabold text-gray-900 leading-none tracking-tight tabular-nums mb-3",
              data: { payment_link_compose_target: "pvAmount" }) { plain "GH₵ 50.00" }
            p(class: "text-[13.5px] font-medium text-gray-500 leading-snug",
              data: { payment_link_compose_target: "pvDescription" }) { plain "Your product" }
          end

          div(class: "h-px bg-gray-100 mx-6")

          # Payment methods
          div(class: "px-6 py-5") do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-3") { plain "Pay with" }
            div(class: "flex flex-wrap gap-2") do
              METHODS.each do |m|
                div(
                  class: "flex items-center gap-1.5 px-3 py-[7px] rounded-[10px] border border-gray-200 " \
                         "text-[12px] font-medium text-gray-700 bg-white",
                  data:  { "pl-method": m[:value] }
                ) do
                  span(class: "text-[14px]") { plain m[:icon] }
                  plain m[:label]
                end
              end
            end
          end

          div(class: "h-px bg-gray-100 mx-6")

          # Customer collect fields
          div(
            class:  "px-6 py-5 flex flex-col gap-2.5",
            hidden: true,
            data:   { payment_link_compose_target: "pvCustomerSection" }
          ) do
            collect_preview_field("email",    "Email address",  "email",    "you@example.com")
            collect_preview_field("phone",    "Phone number",   "tel",      "+233 24 000 0000")
            collect_preview_field("name",     "Full name",      "text",     "Your name")
          end

          # CTA
          div(class: "px-6 pb-6") do
            div(
              class: "w-full py-3.5 rounded-[10px] bg-[#3D47F5] flex items-center justify-center " \
                     "text-[13.5px] font-bold text-white cursor-default",
              data:  { payment_link_compose_target: "pvPayButton" }
            ) { plain "Pay GH₵ 50.00" }
          end

          # Footer
          div(class: "px-6 pb-5 flex items-center justify-center gap-[5px]") do
            span(class: "text-[10px] text-gray-300") { plain "Powered by" }
            span(class: "text-[10px] font-bold text-[#3D47F5]/50") { plain "Yagye" }
          end
        end
      end
    end

    def collect_preview_field(collect_name, label_text, type, placeholder_text)
      div(
        hidden: true,
        data:   { "pl-collect": "collect_#{collect_name}" }
      ) do
        p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") do
          plain label_text
        end
        div(
          class: "w-full h-[38px] border border-gray-200 rounded-[10px] px-3 flex items-center " \
                 "text-[12.5px] text-gray-300"
        ) { plain placeholder_text }
      end
    end

    # ── Shared input styles ───────────────────────────────────────────────────

    def panel_input_cls
      "w-full h-[34px] border border-gray-200 rounded-[9px] px-2.5 text-[12.5px] " \
      "text-gray-700 bg-white outline-none focus:border-[#3D47F5] transition-colors"
    end
  end
end
