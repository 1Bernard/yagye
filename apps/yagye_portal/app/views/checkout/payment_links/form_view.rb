# frozen_string_literal: true

module Checkout
  module PaymentLinks
    class FormView < ApplicationComponent
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

    FONT_OPTIONS = [
      [ "Plus Jakarta Sans (default)", "plus-jakarta" ],
      [ "Inter",                       "inter" ],
      [ "Nunito",                      "nunito" ],
      [ "Playfair Display",            "playfair" ],
      [ "Roboto Slab",                 "roboto-slab" ]
    ].freeze

    CTA_PRESETS = [
      [ "Pay (default)",  "" ],
      [ "Donate",         "Donate" ],
      [ "Register",       "Register" ],
      [ "Book now",       "Book now" ],
      [ "Subscribe",      "Subscribe" ],
      [ "Get started",    "Get started" ]
    ].freeze

    def initialize(errors: [], mode: "test", checkout_config: {})
      @errors          = errors
      @mode            = mode
      @checkout_config = checkout_config
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :payment_links,
        title:       "New payment link",
        breadcrumbs: [
          { label: "Payment Links", href: payment_links_path },
          { label: "New" }
        ],
        padded:      false,
        hide_sidebar: true,
        hide_topbar:  true
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
          div(class: "flex items-center gap-[6px] px-[10px] py-[4px] rounded-xl bg-red-50 border border-red-100") do
            span(class: "text-[10.5px] font-bold text-red-600") do
              plain "#{@errors.size} error#{"s" if @errors.size > 1}:"
            end
            span(class: "text-[10.5px] text-red-700") { plain @errors.first }
          end
        end

        button(
          type:  "submit",
          form:  "pl-form",
          class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                 "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0"
        ) { plain "Create link" }
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
          if @errors.any?
            div(class: "mx-3 mt-3 p-3 rounded-xl bg-red-50 border border-red-100") do
              @errors.each do |msg|
                div(class: "flex items-start gap-[6px]") do
                  span(class: "text-red-500 mt-[1px] flex-shrink-0") { plain "•" }
                  p(class: "text-[12px] text-red-700 leading-snug") { plain msg }
                end
              end
            end
          end
          link_details_section
          section_divider
          payment_methods_section
          section_divider
          collect_section
          section_divider
          usage_section
          section_divider
          escrow_section
          section_divider
          brand_section
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

          # Discount (optional)
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Discount (optional)" }
            input(
              type:        "number",
              name:        "discount_amount",
              min:         "0",
              step:        "0.01",
              placeholder: "0.00",
              class:       "#{panel_input_cls} tabular-nums text-right",
              data:        { action: "input->payment-link-compose#syncDiscountPreview" }
            )
            p(class: "text-[10.5px] text-gray-400 mt-[4px]") { plain "Fixed deduction shown to the customer at checkout" }
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

    # ── Trust Hold (Escrow) ──────────────────────────────────────────────────

    def escrow_section
      div(class: "px-4 pt-3 pb-5") do
        div(class: "flex items-center gap-2 mb-[6px]") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Trust Hold" }
          span(
            class: "text-[9px] font-semibold px-[6px] py-[1px] rounded-full " \
                   "bg-amber-50 text-amber-600 border border-amber-100"
          ) { plain "NEW" }
        end
        p(class: "text-[10.5px] text-gray-400 mb-3 leading-snug") do
          plain "Hold buyer's payment in trust until they confirm receipt. " \
                "Ideal for social commerce and goods delivery."
        end

        div(
          class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] border border-gray-100 " \
                 "hover:border-gray-200 transition-colors mb-3"
        ) do
          input(
            type:  "checkbox",
            name:  "escrow_enabled",
            value: "1",
            id:    "escrow_enabled",
            class: "w-[14px] h-[14px] rounded flex-shrink-0 accent-[#3D47F5] cursor-pointer",
            data:  { action: "change->payment-link-compose#toggleEscrow", payment_link_compose_target: "escrowToggle" }
          )
          div do
            label(
              for:   "escrow_enabled",
              class: "block text-[12px] font-semibold text-gray-800 cursor-pointer leading-tight"
            ) { plain "Enable trust hold" }
            p(class: "text-[10.5px] text-gray-400") do
              plain "Buyer must confirm receipt before merchant is paid"
            end
          end
        end

        div(
          data:   { payment_link_compose_target: "escrowDetails" },
          hidden: true,
          class:  "flex flex-col gap-2"
        ) do
          escrow_number_field(
            "escrow_auto_release_days",
            "Auto-release after",
            "days",
            "7",
            "Funds release to merchant automatically after this many days if buyer takes no action"
          )
          escrow_number_field(
            "escrow_dispute_window_hours",
            "Dispute window",
            "hours",
            "48",
            "How long after payment the buyer can open a dispute"
          )
        end
      end
    end

    def escrow_number_field(field_name, label_text, unit, default_val, hint_text)
      div do
        span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
          plain label_text
        end
        div(class: "flex items-center gap-2") do
          input(
            type:  "number",
            name:  field_name,
            min:   "1",
            value: default_val,
            class: "#{panel_input_cls} tabular-nums",
            style: "width: 80px; flex-shrink: 0"
          )
          span(class: "text-[12px] text-gray-500") { plain unit }
        end
        p(class: "text-[10.5px] text-gray-400 mt-[3px]") { plain hint_text }
      end
    end

    # ── Brand / appearance ───────────────────────────────────────────────────

    def brand_section
      div(class: "px-4 pt-3 pb-5") do
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Appearance" }
        div(class: "flex flex-col gap-2.5") do
          # Brand colour
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
              plain "Brand colour"
            end
            div(class: "flex items-center gap-2") do
              input(
                type:  "color",
                name:  "checkout_config[brand_colour]",
                value: @checkout_config["brand_colour"].presence || "#3D47F5",
                class: "w-8 h-8 rounded-lg border border-gray-200 cursor-pointer p-[2px] bg-white flex-shrink-0",
                data:  { action: "input->payment-link-compose#syncBrand" }
              )
              input(
                type:        "text",
                name:        "checkout_config[brand_colour_text]",
                value:       @checkout_config["brand_colour"].presence || "#3D47F5",
                placeholder: "#3D47F5",
                class:       "#{panel_input_cls} font-mono uppercase",
                style:       "width: 100px; flex-shrink: 0",
                data:        { payment_link_compose_target: "brandHex",
                               action: "input->payment-link-compose#syncBrandHex" }
              )
              span(class: "text-[10.5px] text-gray-400 leading-tight") do
                plain "Buttons, highlights"
              end
            end
          end

          # Display name
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
              plain "Display name"
            end
            input(
              type:        "text",
              name:        "checkout_config[display_name]",
              value:       @checkout_config["display_name"].presence,
              placeholder: "Your business name",
              class:       panel_input_cls,
              data:        { action: "input->payment-link-compose#syncBrand" }
            )
            p(class: "text-[10.5px] text-gray-400 mt-[4px]") do
              plain "Shown on the checkout page and receipt"
            end
          end

          # Font
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
              plain "Font"
            end
            select(
              name:  "checkout_layout[font_family]",
              class: "#{panel_input_cls} cursor-pointer"
            ) do
              FONT_OPTIONS.each do |(label, value)|
                option(value: value) { plain label }
              end
            end
          end

          # Checkout headline
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
              plain "Checkout headline"
            end
            input(
              type:        "text",
              name:        "checkout_layout[headline]",
              placeholder: "e.g. Support our fundraiser",
              class:       panel_input_cls,
              data:        { action: "input->payment-link-compose#syncHeadlinePreview" }
            )
            p(class: "text-[10.5px] text-gray-400 mt-[4px]") { plain "Optional tagline shown above the description" }
          end

          # Button label
          div do
            span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
              plain "Button label"
            end
            select(
              name:  "checkout_layout[cta_text]",
              class: "#{panel_input_cls} cursor-pointer",
              data:  { action: "change->payment-link-compose#syncCtaPreview" }
            ) do
              CTA_PRESETS.each do |(label, value)|
                option(value: value) { plain label }
              end
            end
          end

          # Terms & Conditions
          div do
            div(class: "flex items-center justify-between mb-[5px]") do
              span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Terms & Conditions" }
              label(class: "relative inline-flex items-center cursor-pointer") do
                input(
                  type:  "checkbox",
                  id:    "form_terms_enabled",
                  name:  "checkout_layout[terms_enabled]",
                  value: "1",
                  class: "sr-only peer",
                  data:  { action: "change->payment-link-compose#toggleFormTerms" }
                )
                span(class: "w-7 h-[15px] bg-gray-200 rounded-full peer peer-checked:bg-[#3D47F5] transition-colors") { }
                span(class: "absolute left-[2px] top-[2px] w-[11px] h-[11px] bg-white rounded-full " \
                            "transition-transform peer-checked:translate-x-[13px]") { }
              end
            end
            div(id: "form-terms-fields", style: "display:none", class: "flex flex-col gap-[5px] mt-[5px]") do
              input(
                type:        "text",
                name:        "checkout_layout[terms_label]",
                placeholder: "I agree to the Terms & Conditions",
                class:       panel_input_cls,
                data:        { action: "input->payment-link-compose#syncTermsLabelPreview" }
              )
              input(
                type:        "text",
                name:        "checkout_layout[terms_url]",
                placeholder: "https://yoursite.com/terms",
                class:       panel_input_cls
              )
            end
          end
        end
      end
    end

    # ── Preview area (right) ─────────────────────────────────────────────────

    def preview_area
      bc   = @checkout_config["brand_colour"].presence || "#3D47F5"
      name = @checkout_config["display_name"].presence || "Your business"

      div(
        class: "absolute top-5 right-0 bottom-0 overflow-y-auto",
        style: "left: 385px"
      ) do
        div(class: "min-h-full py-8 px-8 flex flex-col items-center") do
          render Checkout::PaymentLinks::PreviewCardComponent.new(
            brand_color:     bc,
            merchant_name:   name,
            amount_display:  "GH₵ 50.00",
            description:     "Your product",
            allowed_methods: %w[mobile_money card bank_transfer],
            mode:            @mode,
            show_label:      true
          )
        end
      end
    end

    # ── Shared input styles ───────────────────────────────────────────────────

    def panel_input_cls
      "w-full h-[34px] border border-gray-200 rounded-[9px] px-2.5 text-[12.5px] " \
      "text-gray-700 bg-white outline-none focus:border-[#3D47F5] transition-colors"
    end
    end
  end
end
