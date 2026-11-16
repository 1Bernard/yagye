# frozen_string_literal: true

module Checkout
  class CheckoutLayoutView < ApplicationComponent
    include UI::Theme

    def initialize(link:, all_links:, branding: nil, checkout_config: {}, checkout_template: {})
      @link              = link
      @all_links         = all_links
      @branding          = branding
      @checkout_config   = checkout_config
      @checkout_template = checkout_template
    end

    def view_template
      render Layout::Shell.new(
        active_nav:   :payment_links,
        title:        "Checkout layout",
        breadcrumbs:  [
          { label: "Payment Links", href: payment_links_path },
          { label: @link["description"] || @link["id"], href: payment_link_path(@link["id"]) },
          { label: "Checkout layout" }
        ],
        padded:       false,
        hide_sidebar: true,
        hide_topbar:  true
      ) do
        canvas_styles

        div(
          class: "relative h-full overflow-hidden",
          data: {
            controller:                     "checkout-layout",
            checkout_layout_save_url_value: update_layout_url,
            checkout_layout_csrf_value:     form_authenticity_token,
            checkout_layout_mode_value:     @link["mode"].presence || "live"
          }
        ) do
          div(id: "checkout-canvas", class: "absolute inset-0")
          floating_toolbar
          editor_panel
          preview_area
          back_btn_script
        end
      end
    end

    private

    def update_layout_url
      payment_link_layout_path(@link["id"])
    end

    # ── Canvas background ─────────────────────────────────────────────────────

    def canvas_styles
      style do
        raw safe(%(
          #checkout-canvas {
            background-color: #f8fafc;
            background-image: radial-gradient(circle, #d1d5db 1px, transparent 1px);
            background-size: 24px 24px;
          }
        ))
      end
    end

    # ── Floating toolbar (top centre pill) ────────────────────────────────────

    def floating_toolbar
      div(
        class: "absolute top-4 left-1/2 -translate-x-1/2 z-30 flex items-center gap-[6px] " \
               "bg-white border border-gray-200/80 rounded-2xl px-[10px] py-[7px] " \
               "shadow-[0_4px_24px_rgba(0,0,0,0.08)] select-none"
      ) do
        # Back button — uses history.back() so it returns to wherever the user came from
        a(
          id:   "cl-back-btn",
          href: payment_link_path(@link["id"]),
          class: "flex items-center justify-center w-8 h-8 rounded-xl hover:bg-gray-100 " \
                 "text-gray-400 hover:text-gray-700 transition-colors flex-shrink-0"
        ) do
          span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:chev_left, class: "w-full h-full") }
        end

        div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

        # Link name
        p(class: "text-[13.5px] font-semibold text-gray-900 px-1 max-w-[200px] truncate") do
          plain @link["description"] || @link["id"]
        end

        # Mode chip
        span(
          class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full " \
                 "bg-gray-100 text-gray-500"
        ) { plain (@link["mode"] || "simulation").capitalize }

        # Navigation — Overview | Layout
        a(href: payment_link_path(@link["id"]),
          class: "flex items-center gap-[5px] px-[9px] py-[5px] rounded-xl text-[12px] font-medium " \
                 "text-gray-500 hover:bg-gray-100 hover:text-gray-700 transition-colors no-underline") do
          span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:eye, class: "w-full h-full") }
          plain "Overview"
        end
        span(class: "flex items-center gap-[5px] px-[9px] py-[5px] rounded-xl text-[12px] font-semibold " \
                    "text-[#3D47F5]",
             style: "background:rgba(61,71,245,0.10);border:1px solid rgba(61,71,245,0.20)") do
          span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:edit, class: "w-full h-full") }
          plain "Layout"
        end

        if @all_links.size > 1
          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")
          select(
            class: "text-[12px] text-gray-500 bg-transparent border-0 outline-none pr-1 cursor-pointer",
            data: { action: "change->checkout-layout#navigateLink" }
          ) do
            @all_links.each do |l|
              opts = { value: l["id"] }
              opts[:selected] = "selected" if l["id"] == @link["id"]
              option(**opts) { plain l["description"] || l["id"] }
            end
          end
        end

        div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

        # Saved badge (hidden until save completes)
        span(
          class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-green-50 text-green-600",
          hidden: true,
          data: { checkout_layout_target: "savedBadge" }
        ) { plain "Saved" }

        # Save
        button(
          type:  "button",
          class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                 "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0",
          data: {
            action:                 "click->checkout-layout#save",
            checkout_layout_target: "saveBtn"
          }
        ) { plain "Save layout" }
      end
    end

    # ── Left editor panel (floating glass) ────────────────────────────────────

    def editor_panel
      div(
        class: "absolute top-[76px] left-5 bottom-5 z-20 w-[308px] flex flex-col " \
               "bg-white border border-gray-200/70 rounded-2xl overflow-hidden " \
               "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]"
      ) do
        # Panel label
        div(class: "flex items-center px-4 pt-[14px] pb-3 flex-shrink-0") do
          p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-500") do
            plain "Layout"
          end
        end

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")

        div(class: "flex-1 overflow-y-auto") do
        # Branding
        div(class: "px-3 pt-2 pb-3") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-[7px]") { plain "Branding" }

          if @branding&.logo&.attached?
            logo_url = @branding.logo_url
            div(class: "flex items-center gap-2") do
              img(src: logo_url, alt: "Logo",
                  class: "w-8 h-8 rounded-lg object-contain border border-gray-100 bg-white flex-shrink-0",
                  data: { checkout_layout_target: "previewLogoImg" })
              div(class: "flex-1 min-w-0") do
                p(class: "text-[10px] font-semibold text-gray-700 truncate") do
                  plain @branding.display_name.presence || "Your logo"
                end
                a(href: settings_path(tab: "verification"),
                  class: "text-[10px] text-[#3D47F5] hover:underline") { plain "Change in Settings →" }
              end
            end
            input(type: "hidden", value: logo_url,
                  data: { checkout_layout_target: "logoUrlInput",
                          action: "input->checkout-layout#updateLogo" })
          else
            div(class: "flex items-center gap-[7px] px-[10px] py-[9px] bg-gray-50 rounded-xl border border-dashed border-gray-200") do
              span(class: "flex w-[14px] h-[14px] text-gray-300 flex-shrink-0") do
                render UI::Icon.new(:upload, class: "w-full h-full")
              end
              div do
                p(class: "text-[10px] font-medium text-gray-500 leading-tight") { plain "No logo uploaded" }
                a(href: settings_path(tab: "verification"),
                  class: "text-[10px] text-[#3D47F5] hover:underline leading-tight") do
                  plain "Upload in Settings →"
                end
              end
            end
          end
        end

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")
        appearance_section
        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")
        content_section
        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")
        cta_section
        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")
        terms_section
        end # scrollable body
      end
    end

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

    def section_label(text)
      p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-[7px]") { plain text }
    end

    def input_field(name:, value:, placeholder: "", data: {})
      input(
        type:        "text",
        name:        name,
        value:       value.to_s,
        placeholder: placeholder,
        class:       "w-full text-[11.5px] text-gray-700 bg-gray-50 border border-gray-200 " \
                     "rounded-lg px-[9px] py-[6px] outline-none focus:border-[#3D47F5] " \
                     "focus:ring-1 focus:ring-[#3D47F5]/20 transition placeholder-gray-300",
        data:        data
      )
    end

    def appearance_section
      saved_color = @checkout_config["brand_colour"].presence || "#3D47F5"
      saved_font  = @checkout_template.dig("theme", "font_family").to_s

      div(class: "px-3 pt-2 pb-3 flex-shrink-0") do
        section_label("Appearance")

        # Brand color row
        div(class: "flex items-center gap-[6px] mb-[7px]") do
          div(class: "relative flex-shrink-0") do
            input(
              type:  "color",
              value: saved_color,
              class: "w-7 h-7 rounded-md cursor-pointer border border-gray-200 p-0 bg-white",
              style: "appearance:none;-webkit-appearance:none;padding:1px;",
              data:  { action: "input->checkout-layout#syncColorHex" }
            )
          end
          input_field(
            name:        "brand_color_hex",
            value:       saved_color,
            placeholder: "#3D47F5",
            data:        { action: "input->checkout-layout#updateBrandColor", preview_color_hex: "" }
          )
        end

        # Font selector
        select(
          class: "w-full text-[11.5px] text-gray-700 bg-gray-50 border border-gray-200 " \
                 "rounded-lg px-[9px] py-[6px] outline-none cursor-pointer",
          data:  { action: "change->checkout-layout#updateFont" }
        ) do
          FONT_OPTIONS.each do |(label, value)|
            opts = { value: value }
            opts[:selected] = "selected" if saved_font == value
            option(**opts) { plain label }
          end
        end
      end
    end

    def content_section
      saved_name     = @checkout_config["display_name"].to_s
      saved_headline = @link.dig("checkout_layout", "headline").to_s

      div(class: "px-3 pt-2 pb-3 flex-shrink-0") do
        section_label("Content")

        div(class: "flex flex-col gap-[6px]") do
          div do
            p(class: "text-[9.5px] text-gray-400 mb-[3px]") { plain "Business name (optional override)" }
            input_field(
              name:        "business_name",
              value:       saved_name,
              placeholder: @branding&.display_name.presence || "Your business name",
              data:        { action: "input->checkout-layout#updateBusinessName" }
            )
          end
          div do
            p(class: "text-[9.5px] text-gray-400 mb-[3px]") { plain "Checkout headline (optional)" }
            input_field(
              name:        "headline",
              value:       saved_headline,
              placeholder: "e.g. Support our fundraiser",
              data:        { action: "input->checkout-layout#updateHeadline" }
            )
          end
        end
      end
    end

    def cta_section
      saved_cta = @link.dig("checkout_layout", "cta_text").to_s

      div(class: "px-3 pt-2 pb-3 flex-shrink-0") do
        section_label("Button label")

        select(
          class: "w-full text-[11.5px] text-gray-700 bg-gray-50 border border-gray-200 " \
                 "rounded-lg px-[9px] py-[6px] outline-none cursor-pointer",
          data:  { action: "change->checkout-layout#updateCta" }
        ) do
          CTA_PRESETS.each do |(label, value)|
            opts = { value: value }
            opts[:selected] = "selected" if saved_cta == value
            option(**opts) { plain label }
          end
        end
      end
    end

    def terms_section
      terms        = @link.dig("checkout_layout", "terms") || {}
      enabled      = terms["enabled"] == true
      saved_label  = terms["label"].presence || "I agree to the Terms & Conditions"
      saved_url    = terms["url"].to_s

      div(class: "px-3 pt-2 pb-3 flex-shrink-0") do
        section_label("Terms & Conditions")

        # Enable toggle row
        div(class: "flex items-center justify-between mb-[7px]") do
          p(class: "text-[11px] text-gray-600") { plain "Require acceptance before payment" }
          label(class: "relative inline-flex items-center cursor-pointer") do
            input(
              type:    "checkbox",
              class:   "sr-only peer",
              checked: enabled ? true : nil,
              data:    { action: "change->checkout-layout#toggleTerms", terms_toggle: "" }
            )
            span(class: "w-7 h-[15px] bg-gray-200 rounded-full peer peer-checked:bg-[#3D47F5] transition-colors") { }
            span(class: "absolute left-[2px] top-[2px] w-[11px] h-[11px] bg-white rounded-full " \
                        "transition-transform peer-checked:translate-x-[13px]") { }
          end
        end

        div(
          class: "flex flex-col gap-[5px] overflow-hidden transition-all",
          style: enabled ? "" : "display:none",
          data:  { terms_fields: "" }
        ) do
          input_field(
            name:        "terms_label",
            value:       saved_label,
            placeholder: "I agree to the Terms & Conditions",
            data:        { action: "input->checkout-layout#updateTermsLabel" }
          )
          input_field(
            name:        "terms_url",
            value:       saved_url,
            placeholder: "https://yoursite.com/terms",
            data:        { action: "input->checkout-layout#updateTermsUrl" }
          )
        end
      end
    end

    # ── Right preview area ────────────────────────────────────────────────────

    def preview_area
      cl             = @link["checkout_layout"] || {}
      brand_color    = @checkout_config["brand_colour"].presence || cl["brand_color"].presence || "#3D47F5"
      saved_logo     = @checkout_config["logo_url"].presence || ""
      default_name   = @branding&.display_name.presence || "Your business"
      merchant_name  = @checkout_config["display_name"].presence || cl["business_name"].presence || default_name
      sym            = currency_symbol(@link["currency"].to_s)
      amt            = @link["amount"].to_i
      amount_display = amt > 0 ? "#{sym} #{format_amount(amt)}" : "You choose"
      cta_text       = cl["cta_text"].presence || (amt > 0 ? "Pay #{sym} #{format_amount(amt)}" : "Pay now")
      saved_headline = cl["headline"].to_s.presence
      terms_config   = cl["terms"] || {}
      terms_data     = if terms_config["enabled"] == true
        { label: terms_config["label"].presence || "I agree to the Terms & Conditions",
          url:   terms_config["url"].to_s }
      end

      div(
        class: "absolute top-[76px] right-0 bottom-0 flex flex-col items-center justify-start pt-5 pb-5 " \
               "overflow-y-auto",
        style: "left: 348px"
      ) do
        wa_text = CGI.escape("#{@link["description"].presence || "Pay here"}: #{@link["checkout_url"]}")
        div(
          class: "w-full max-w-[900px] flex items-center gap-0 mb-5 bg-white border border-gray-200/80 " \
                 "rounded-2xl overflow-hidden shadow-[0_4px_20px_rgba(0,0,0,0.06)] select-none"
        ) do
          div(class: "flex items-center gap-2.5 flex-1 min-w-0 px-4 py-[9px]") do
            span(class: "text-[10px] font-bold uppercase tracking-[0.1em] text-gray-300 flex-shrink-0") { plain "Share" }
            span(class: "w-px h-3 bg-gray-200 flex-shrink-0")
            a(
              href:   @link["checkout_url"],
              target: "_blank",
              rel:    "noopener noreferrer",
              class:  "font-mono text-[11px] text-[#3D47F5] hover:underline truncate",
              data:   { checkout_layout_target: "checkoutUrl" }
            ) { plain @link["checkout_url"] }
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          button(
            type:  "button",
            class: "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                   "text-gray-500 hover:bg-gray-50 hover:text-gray-700 transition-colors cursor-pointer",
            data:  { action: "click->checkout-layout#copyUrl",
                     checkout_layout_target: "copyUrlBtn" }
          ) do
            render UI::Icon.new(:copy, class: "w-3.5 h-3.5")
            plain "Copy"
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          a(
            href:   "https://wa.me/?text=#{wa_text}",
            target: "_blank",
            rel:    "noopener noreferrer",
            class:  "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                    "text-gray-500 hover:bg-gray-50 hover:text-gray-700 transition-colors no-underline"
          ) do
            span(class: "text-[13px] leading-none") { plain "💬" }
            plain "WhatsApp"
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          a(
            href:   payment_link_display_path(@link["id"]),
            target: "_blank",
            rel:    "noopener noreferrer",
            class:  "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                    "text-gray-500 hover:bg-gray-50 hover:text-gray-700 transition-colors no-underline"
          ) do
            render UI::Icon.new(:qr_code, class: "w-3.5 h-3.5")
            plain "QR"
          end
        end

        render Checkout::PaymentLinks::PreviewCardComponent.new(
          brand_color:     brand_color,
          merchant_name:   merchant_name,
          logo_url:        saved_logo,
          amount_display:  amount_display,
          description:     @link["description"].presence || "Payment",
          allowed_methods: Array(@link["allowed_methods"]),
          collect_email:   @link["collect_email"],
          collect_phone:   @link["collect_phone"],
          collect_name:    @link["collect_name"],
          cta_text:        cta_text,
          escrow_enabled:  @link["escrow_enabled"],
          mode:            @link["mode"],
          show_label:      false,
          headline:        saved_headline,
          terms:           terms_data
        )
      end
    end

    def back_btn_script
      script(nonce: content_security_policy_nonce) do
        raw safe(<<~JS)
          (function () {
            var btn = document.getElementById('cl-back-btn');
            if (!btn) return;
            btn.addEventListener('click', function (e) {
              if (history.length > 1) {
                e.preventDefault();
                history.back();
              }
              // else: let the href fallback navigate to the show page
            });
          })();
        JS
      end
    end

    def currency_symbol(code)
      { "GHS" => "GH₵", "USD" => "$", "EUR" => "€", "GBP" => "£", "NGN" => "₦" }
        .fetch(code.to_s, code.to_s)
    end

    def format_amount(minor_units)
      n = minor_units.to_f / 100
      whole, frac = sprintf("%.2f", n).split(".")
      "#{whole.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}.#{frac}"
    end
  end
end
