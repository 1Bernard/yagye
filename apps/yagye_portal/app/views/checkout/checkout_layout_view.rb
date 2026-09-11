# frozen_string_literal: true

module Checkout
  class CheckoutLayoutView < ApplicationComponent
    include UI::Theme

    DEFAULT_METHODS = [
      {
        "id"         => "mobile_money",
        "label"      => "Mobile Money",
        "visible"    => true,
        "tile_style" => "expanded",
        "rails"      => [
          { "id" => "mtn_momo",     "label" => "MTN MoMo",       "visible" => true },
          { "id" => "telecel_cash", "label" => "Telecel Cash",    "visible" => true },
          { "id" => "airteltigo",   "label" => "AirtelTigo Cash", "visible" => true }
        ]
      },
      {
        "id"         => "card",
        "label"      => "Card",
        "visible"    => false,
        "tile_style" => "compact",
        "rails"      => [
          { "id" => "stripe", "label" => "Stripe", "visible" => true }
        ]
      },
      {
        "id"         => "bank_transfer",
        "label"      => "Bank Transfer",
        "visible"    => false,
        "tile_style" => "compact",
        "rails"      => []
      }
    ].freeze

    METHOD_ICONS = {
      "mobile_money"  => "phone",
      "card"          => "credit_card",
      "bank_transfer" => "building"
    }.freeze

    METHOD_COLORS = {
      "mobile_money"  => { bg: "rgba(61,71,245,0.09)",  icon: "#3D47F5" },
      "card"          => { bg: "rgba(16,185,129,0.09)", icon: "#10b981" },
      "bank_transfer" => { bg: "rgba(245,158,11,0.09)", icon: "#f59e0b" }
    }.freeze

    def initialize(link:, all_links:)
      @link      = link
      @all_links = all_links
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payment_links,
        title:      @link["description"] || "Checkout layout",
        breadcrumbs: [
          { label: "Payment Links", href: payment_links_path },
          { label: @link["description"] || @link["id"] }
        ],
        padded: false
      ) do
        canvas_styles

        div(
          class: "relative h-full overflow-hidden",
          data: {
            controller:                     "checkout-layout",
            checkout_layout_save_url_value: update_layout_url,
            checkout_layout_csrf_value:     form_authenticity_token
          }
        ) do
          div(id: "checkout-canvas", class: "absolute inset-0")
          floating_toolbar
          editor_panel
          preview_area
        end
      end
    end

    private

    def update_layout_url
      payment_link_layout_path(@link["id"])
    end

    def methods_to_render
      saved = @link["checkout_layout"]&.fetch("methods", nil)
      saved.present? ? saved : DEFAULT_METHODS
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
          [data-method-id] .tile-header { cursor: grab; user-select: none; }
          [data-method-id] .tile-header:active { cursor: grabbing; }
          [data-method-id] .tile-header input,
          [data-method-id] .tile-header label { cursor: pointer; }
          .tile-style-btn { color: #6b7280; flex: 1; text-align: center; border-radius: 6px; transition: color 0.12s; }
          .tile-style-btn:hover { color: #374151; }
          .tile-style-btn:has(input:checked) { background: white !important; color: #111827 !important; box-shadow: 0 1px 2px rgba(0,0,0,0.10); }
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
        # Back
        a(
          href: payment_links_path,
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
        div(class: "flex items-center justify-between px-4 pt-[14px] pb-3 flex-shrink-0") do
          p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-500") do
            plain "Payment methods"
          end
          p(class: "text-[10px] text-gray-400") { plain "drag · toggle · style" }
        end

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")

        # Branding
        div(class: "px-3 pt-2 pb-3 flex-shrink-0") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-[7px]") { plain "Branding" }
          label(class: "text-[10px] font-semibold text-gray-500 block mb-[5px]") { plain "Logo URL" }
          input(
            type:        "url",
            placeholder: "https://example.com/logo.png",
            value:       @link.dig("checkout_layout", "logo_url").to_s,
            class:       "w-full text-[11px] border border-gray-200 rounded-lg px-2 py-[6px] " \
                         "outline-none focus:border-[#3D47F5] text-gray-700 placeholder-gray-300",
            data: {
              checkout_layout_target: "logoUrlInput",
              action:                 "input->checkout-layout#updateLogo"
            }
          )
        end

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 px-3 pb-2 pt-1 flex-shrink-0") do
          plain "Payment methods"
        end

        # Sortable list
        div(
          class: "flex-1 overflow-y-auto px-3 pb-3 flex flex-col gap-[6px]",
          data: { checkout_layout_target: "methodList" }
        ) do
          methods_to_render.each { |m| method_tile(m) }
        end
      end
    end

    def method_tile(method)
      visible    = method["visible"] != false
      tile_style = method["tile_style"] || "compact"
      icon       = METHOD_ICONS[method["id"]] || "credit_card"
      colors     = METHOD_COLORS[method["id"]] || { bg: "rgba(107,114,128,0.09)", icon: "#6b7280" }

      div(
        class: "bg-white border rounded-xl overflow-hidden " \
               "#{visible ? 'border-gray-200' : 'border-gray-100 opacity-60'}",
        data:  { method_id: method["id"], method_label: method["label"], visible: visible.to_s }
      ) do
        # Header row — pointer drag starts here (skip interactive children)
        div(class: "tile-header flex items-center gap-2.5 px-3 py-2.5") do
          span(class: "text-gray-300 flex-shrink-0 pointer-events-none") do
            render UI::Icon.new(:grip, class: "w-4 h-4")
          end

          # Coloured icon bubble
          span(
            class: "w-6 h-6 rounded-lg flex items-center justify-center flex-shrink-0",
            style: "background:#{colors[:bg]}"
          ) do
            span(class: "flex w-[12px] h-[12px]", style: "color:#{colors[:icon]}") do
              render UI::Icon.new(icon.to_sym, class: "w-full h-full")
            end
          end

          # Name
          span(class: "flex-1 text-[12.5px] font-semibold text-gray-800 leading-tight") do
            plain method["label"]
          end

          # Visibility toggle
          label(class: "relative inline-flex items-center cursor-pointer flex-shrink-0") do
            input(
              type:    "checkbox",
              class:   "sr-only peer",
              checked: visible ? true : nil,
              data: {
                role:   "method-toggle",
                action: "change->checkout-layout#toggleMethod"
              }
            )
            span(
              class: "w-7 h-[15px] bg-gray-200 rounded-full peer " \
                     "peer-checked:bg-[#3D47F5] transition-colors"
            ) { }
            span(
              class: "absolute left-[2px] top-[2px] w-[11px] h-[11px] bg-white rounded-full " \
                     "transition-transform peer-checked:translate-x-[13px]"
            ) { }
          end
        end

        # Style segmented pill (no label — Compact/Expanded speak for themselves)
        div(class: "px-3 pb-[10px]") do
          div(class: "flex items-center bg-gray-100 rounded-lg p-[3px] gap-[2px]") do
            tile_style_btn(method["id"], tile_style, "compact",  "Compact")
            tile_style_btn(method["id"], tile_style, "expanded", "Expanded")
          end
        end

        # Networks section with centered rule label
        if method["rails"]&.any?
          div(class: "border-t border-gray-50 px-3 pt-2 pb-[10px]") do
            div(class: "flex items-center gap-2 mb-[7px]") do
              div(class: "h-px flex-1 bg-gray-100")
              span(class: "text-[9px] font-semibold uppercase tracking-[0.12em] text-gray-400") { plain "Networks" }
              div(class: "h-px flex-1 bg-gray-100")
            end
            div(class: "flex flex-col gap-[2px]") do
              method["rails"].each { |rail| rail_row(rail) }
            end
          end
        end
      end
    end

    def tile_style_btn(method_id, current, value, label)
      active = current == value
      label(class: "tile-style-btn text-[10.5px] font-medium py-[4px] cursor-pointer") do
        input(
          type:    "radio",
          name:    "tile_style_#{method_id}",
          value:   value,
          class:   "sr-only",
          checked: active ? true : nil,
          data:    { role: "tile-style", action: "change->checkout-layout#setTileStyle" }
        )
        plain label
      end
    end

    def rail_row(rail)
      visible = rail["visible"] != false
      div(
        class: "flex items-center gap-2 py-[3px]",
        data:  { rail_id: rail["id"], rail_label: rail["label"] }
      ) do
        span(class: "w-[5px] h-[5px] rounded-full bg-gray-200 flex-shrink-0") {}
        span(class: "flex-1 text-[11.5px] font-medium text-gray-500") { plain rail["label"] }
        input(
          type:    "checkbox",
          class:   "w-[13px] h-[13px] accent-[#3D47F5] cursor-pointer flex-shrink-0",
          checked: visible ? true : nil,
          data:    { role: "rail-toggle", action: "change->checkout-layout#toggleRail" }
        )
      end
    end

    # ── Right preview area ────────────────────────────────────────────────────

    def preview_area
      div(
        class: "absolute top-[76px] right-0 bottom-0 flex flex-col items-center justify-start pt-5 pb-5 " \
               "overflow-y-auto",
        style: "left: 348px"
      ) do
        # Share URL pill
        div(
          class: "flex items-center gap-2 mb-5 px-4 py-[7px] bg-white border border-gray-200/80 " \
                 "rounded-2xl shadow-[0_2px_8px_rgba(0,0,0,0.05)] text-[11.5px] " \
                 "shadow-[0_4px_24px_rgba(0,0,0,0.06)]"
        ) do
          span(class: "text-[10.5px] font-bold uppercase tracking-[0.08em] text-gray-300") { plain "Share" }
          span(class: "w-px h-3 bg-gray-200")
          a(
            href:   @link["checkout_url"],
            target: "_blank",
            class:  "font-mono text-[11px] text-[#3D47F5] hover:underline",
            data:   { checkout_layout_target: "checkoutUrl" }
          ) { plain @link["checkout_url"] }
        end

        checkout_card_preview
      end
    end

    def checkout_card_preview
      div(
        class: "w-[360px] bg-white rounded-2xl border border-gray-200/70 overflow-hidden " \
               "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]"
      ) do
        # Header
        div(class: "px-5 pt-5 pb-[18px]") do
          div(class: "flex items-center justify-between mb-4") do
            div(class: "flex items-center gap-2") do
              # Logo: shows img when URL set, icon bubble otherwise
              saved_logo = @link.dig("checkout_layout", "logo_url").to_s
              if saved_logo.present?
                img(
                  src:   saved_logo,
                  alt:   "Logo",
                  class: "w-7 h-7 rounded-lg object-cover flex-shrink-0 border border-gray-100",
                  data:  { checkout_layout_target: "previewLogoImg" }
                )
              else
                div(
                  class: "w-7 h-7 rounded-lg bg-[#3D47F5] flex items-center justify-center",
                  data:  { checkout_layout_target: "previewLogoImg" }
                ) do
                  span(class: "flex w-[13px] h-[13px] text-white") { render UI::Icon.new(:shield, class: "w-full h-full") }
                end
              end
              span(class: "text-[12px] font-bold text-gray-900 tracking-tight") { plain "Yagye" }
            end
            span(
              class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500"
            ) { plain (@link["mode"] || "simulation").capitalize }
          end

          p(class: "text-[11.5px] font-medium text-gray-400 leading-snug mb-[6px]") do
            plain @link["description"] || "Complete your payment"
          end
          if @link["amount"]
            p(class: "text-[30px] font-extrabold text-gray-900 tabular-nums leading-none") do
              plain "#{currency_symbol(@link["currency"])}#{format_amount(@link["amount"])}"
            end
          else
            p(class: "text-[13px] text-gray-500") { plain "Amount set at checkout" }
          end
        end

        div(class: "h-px bg-gray-100")

        # Method list
        div(
          class: "px-4 pt-4 pb-3 flex flex-col gap-[6px]",
          data:  { checkout_layout_target: "previewList" }
        ) do
          p(class: "text-[9px] font-bold uppercase tracking-[0.14em] text-gray-400 mb-1") do
            plain "Select payment method"
          end
          methods_to_render.each { |m| preview_method_tile(m) }
          p(
            class: "text-center text-[12px] text-gray-300 py-4",
            data:  { checkout_layout_target: "emptyPreview" },
            hidden: methods_to_render.any? { |m| m["visible"] != false }
          ) { plain "No methods enabled" }
        end

        # Pay button
        div(class: "px-4 pb-4") do
          div(
            class: "w-full py-[11px] rounded-xl text-[13px] font-semibold text-white " \
                   "bg-[#3D47F5] flex items-center justify-center gap-[6px] " \
                   "pointer-events-none select-none"
          ) do
            if @link["amount"]
              plain "Pay #{currency_symbol(@link["currency"])}#{format_amount(@link["amount"])}"
            else
              plain "Continue"
            end
            span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
          end
        end

        # Footer
        div(class: "px-4 py-3 border-t border-gray-100 flex items-center justify-center gap-[5px]") do
          span(class: "flex w-[10px] h-[10px] text-gray-300") { render UI::Icon.new(:lock, class: "w-full h-full") }
          span(class: "text-[9.5px] text-gray-300") { plain "Secured by" }
          span(class: "text-[9.5px] font-bold text-[#3D47F5]") { plain "Yagye" }
        end
      end
    end

    def preview_method_tile(method)
      icon     = METHOD_ICONS[method["id"]] || "credit_card"
      colors   = METHOD_COLORS[method["id"]] || { bg: "rgba(107,114,128,0.09)", icon: "#6b7280" }
      expanded = method["tile_style"] == "expanded"

      div(
        class: if expanded
          "rounded-xl overflow-hidden bg-white border-2 border-[#3D47F5] " \
          "shadow-[0_4px_20px_rgba(61,71,245,0.13)]"
        else
          "rounded-xl overflow-hidden bg-white border border-gray-200"
        end,
        data: { preview_method: method["id"] }
      ) do
        # Header row
        div(class: "flex items-center gap-3 px-4 py-3") do
          # Radio — filled solid when selected
          div(
            class: "w-[17px] h-[17px] rounded-full flex items-center justify-center flex-shrink-0 " \
                   "#{expanded ? 'bg-[#3D47F5] border-2 border-[#3D47F5]' : 'border-2 border-gray-300'}"
          ) do
            div(class: "w-[6px] h-[6px] rounded-full bg-white") {} if expanded
          end

          # Icon bubble
          span(
            class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
            style: "background:#{colors[:bg]}"
          ) do
            span(class: "flex w-[16px] h-[16px]", style: "color:#{colors[:icon]}") do
              render UI::Icon.new(icon.to_sym, class: "w-full h-full")
            end
          end

          # Method name
          span(
            class: "flex-1 text-[13.5px] font-semibold " \
                   "#{expanded ? 'text-gray-900' : 'text-gray-700'}"
          ) { plain method["label"] }

          # Chevron
          span(class: "flex w-[15px] h-[15px] flex-shrink-0 " \
                      "#{expanded ? 'text-[#3D47F5]' : 'text-gray-400'}") do
            render UI::Icon.new(expanded ? :chev_up : :chev, class: "w-full h-full")
          end
        end

        # Network tiles — 3-col grid matching the checkout UI
        if method["rails"]&.any?
          div(
            class: "#{expanded ? '' : 'hidden'} border-t border-gray-100 px-3 pt-2 pb-3",
            data:  { preview_rails_for: method["id"] }
          ) do
            div(class: "grid grid-cols-3 gap-[5px]") do
              method["rails"].each do |rail|
                visible_rail = rail["visible"] != false
                div(
                  class: "flex flex-col items-center gap-[5px] py-[8px] px-1 " \
                         "rounded-lg border border-gray-100 bg-gray-50/60",
                  data:  { preview_rail: rail["id"] },
                  hidden: !visible_rail
                ) do
                  span(class: "w-[22px] h-[22px] rounded-full overflow-hidden flex-shrink-0 flex") do
                    raw safe(rail_svg(rail["id"]))
                  end
                  span(class: "text-[9px] font-semibold text-gray-600 text-center leading-tight") do
                    plain rail["label"]
                  end
                end
              end
            end
          end
        end
      end
    end

    def rail_svg(id)
      case id
      when "mtn_momo"
        %(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="16" fill="#FFCC00"/><path d="M7 16c0-4.97 4.03-9 9-9s9 4.03 9 9-4.03 9-9 9-9-4.03-9-9z" fill="#002B49"/><path d="M12 19.5v-7l3 4.5 3-4.5v7" stroke="#FFCC00" stroke-width="2" stroke-linecap="round"/></svg>)
      when "telecel_cash"
        %(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><circle cx="16" cy="16" r="16" fill="#E60000"/><circle cx="16" cy="16" r="10" stroke="#FFF" stroke-width="2.5" fill="none"/><path d="M16 11v10M12 15h8" stroke="#FFF" stroke-width="2.5" stroke-linecap="round"/></svg>)
      when "airteltigo"
        %(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><circle cx="16" cy="16" r="16" fill="#1A2B4C"/><path d="M0 16a16 16 0 0 0 32 0H0z" fill="#ED1C24"/><text x="16" y="19" font-family="Inter,sans-serif" font-size="12" font-weight="900" fill="#FFF" text-anchor="middle">at</text></svg>)
      else
        %(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><circle cx="16" cy="16" r="16" fill="#E5E7EB"/></svg>)
      end
    end

    def currency_symbol(code)
      { "GHS" => "GH₵", "USD" => "$", "EUR" => "€", "GBP" => "£", "NGN" => "₦" }
        .fetch(code.to_s, code.to_s)
    end

    def format_amount(minor_units)
      "%.2f" % (minor_units.to_f / 100.0)
    end
  end
end
