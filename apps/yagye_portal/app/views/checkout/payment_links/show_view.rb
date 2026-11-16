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

      def initialize(link:, analytics: {}, checkout_config: {})
        @link            = link
        @analytics       = analytics
        @checkout_config = checkout_config
      end

      def view_template
        @can_layout = can?(:manage_layout?, :checkout)

        render Layout::Shell.new(
          active_nav:   :payment_links,
          title:        @link["description"] || @link["id"],
          breadcrumbs:  [
            { label: "Payment Links", href: payment_links_path },
            { label: @link["description"] || @link["id"].to_s.first(16) }
          ],
          padded:       false,
          hide_sidebar: true,
          hide_topbar:  true
        ) do
          canvas_styles

          div(class: "relative h-full overflow-hidden") do
            div(id: "pl-show-canvas", class: "absolute inset-0")
            floating_toolbar
            div(
              class: "absolute top-[76px] left-0 right-0 bottom-0",
              **(@can_layout ? {
                data: {
                  controller:                     "checkout-layout",
                  checkout_layout_save_url_value: payment_link_layout_path(@link["id"]),
                  checkout_layout_csrf_value:     form_authenticity_token,
                  checkout_layout_mode_value:     @link["mode"].presence || "live"
                }
              } : {})
            ) do
              details_panel
              preview_area
            end
          end

          preview_sync_script
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
            span(class: "#{BADGE_XS} #{STATUS_SUCCESS}") { plain "Active" }
          else
            span(class: "#{BADGE_XS} #{STATUS_NEUTRAL}") { plain "Inactive" }
          end

          span(class: "#{BADGE_XS} #{STATUS_NEUTRAL}") do
            plain (@link["mode"] || "simulation").capitalize
          end

          span(class: "#{BADGE_XS} #{STATUS_NEUTRAL} flex items-center gap-[4px]") do
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
        editable = @link["kind"] != "invoice" && can?(:create?, :checkout)

        div(
          class: "absolute top-5 left-5 bottom-5 z-20 w-[320px] flex flex-col " \
                 "bg-white border border-gray-200/70 rounded-2xl overflow-hidden " \
                 "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]",
          **(editable ? { data: { controller: "inline-edit" } } : {})
        ) do
          if editable
            # ── Display header + body ─────────────────────────────────────────
            div(data: { "inline-edit-target" => "display" }, class: "flex flex-col flex-1 overflow-hidden") do
              panel_header_display
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
                layout_appearance_block if @can_layout
              end
            end

            # ── Edit header + form (hidden until trigger clicked) ─────────────
            div(data: { "inline-edit-target" => "form" }, hidden: true,
                class: "flex flex-col flex-1 overflow-hidden") do
              panel_header_edit
              div(class: "flex-1 overflow-y-auto") do
                settings_form_section
                layout_appearance_block if @can_layout
              end
            end
          else
            panel_header_display
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
              layout_appearance_block if @can_layout
            end
          end
        end
      end

      def panel_header_display
        div(class: "flex items-center justify-between px-4 pt-[14px] pb-[10px] flex-shrink-0") do
          p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Link details" }
          div(class: "flex items-center gap-2") do
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
            button(
              type:  "button",
              class: "flex items-center gap-[4px] ml-1 px-2 py-[3px] rounded-lg " \
                     "text-[10.5px] font-medium text-gray-400 hover:text-gray-700 hover:bg-gray-100 " \
                     "transition-colors cursor-pointer border-0 bg-transparent",
              data:  { "inline-edit-target" => "trigger", action: "inline-edit#edit" }
            ) do
              span(class: "flex w-[10px] h-[10px]") { render UI::Icon.new(:edit, class: "w-full h-full") }
              plain "Edit"
            end
          end
        end
        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")
      end

      def panel_header_edit
        div(class: "flex items-center justify-between px-4 pt-[14px] pb-[10px] flex-shrink-0") do
          p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-[#3D47F5]") { plain "Edit settings" }
          span(class: "flex items-center gap-[4px] text-[10.5px] font-medium text-gray-400") do
            plain "Changes saved on submit"
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
                plain fmt_num(@link["amount"].to_i)
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
            plain @link["inserted_at"] ? (fmt_date(Time.parse(@link["inserted_at"])) rescue "—") : "—"
          end
        end
      end

      # ── Payment methods (display) ─────────────────────────────────────────────

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

      # ── Collect from customer (display) ──────────────────────────────────────

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

      # ── Usage & expiry (display) ──────────────────────────────────────────────

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
              val = begin
                fmt_datetime_utc(Time.parse(@link["expires_at"]))
              rescue ArgumentError, TypeError
                @link["expires_at"]
              end
              plain val
            end
          else
            detail_row("Expires", "No expiry")
          end
        end
      end

      # ── Settings form (edit mode — hidden by default) ─────────────────────────

      def settings_form_section
        methods = Array(@link["allowed_methods"])

        form(
          action: payment_link_settings_path(@link["id"]),
          method: "post",
          data:   { preview_form: "" }
        ) do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          # Immutable-fields notice
          div(class: "px-4 pt-3 pb-1") do
            p(class: "text-[10.5px] text-gray-400 italic leading-relaxed") do
              plain "Amount, currency and payment type are fixed at creation and cannot be changed."
            end
          end

          # Description
          divider
          div(class: "px-4 pt-3 pb-4") do
            section_label("Description")
            textarea(
              name:        "description",
              rows:        "2",
              placeholder: "e.g. School fees — Term 2",
              class:       "#{INPUT_FIELD} resize-none w-full"
            ) { plain @link["description"].to_s }
          end

          # Methods
          divider
          div(class: "px-4 pt-3 pb-4") do
            section_label("Payment methods")
            p(class: "text-[11px] text-gray-400 mb-3") { plain "At least one must remain enabled." }
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
                          class: "block text-[12.5px] font-semibold text-gray-800 cursor-pointer leading-tight") do
                      plain m[:label]
                    end
                    p(class: "text-[10.5px] text-gray-400 leading-tight mt-[1px]") { plain m[:detail] }
                  end
                end
              end
            end
          end

          # Collect from customer
          divider
          div(class: "px-4 pt-3 pb-4") do
            section_label("Collect from customer")
            div(class: "flex flex-col gap-[6px]") do
              [
                %w[collect_email Email\ address],
                %w[collect_phone Phone\ number],
                %w[collect_name Full\ name]
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
                        class: "block text-[12.5px] font-semibold text-gray-800 cursor-pointer leading-tight") do
                    plain label_text
                  end
                end
              end
            end
          end

          # Usage & expiry — reusable links only
          if @link["reusable"]
            divider
            div(class: "px-4 pt-3 pb-4") do
              section_label("Usage & expiry")
              div(class: "flex flex-col gap-3") do
                div do
                  label(class: "block text-[10px] font-semibold text-gray-500 mb-[5px]") { plain "Maximum uses" }
                  input(type:        "number",
                        name:        "max_uses",
                        min:         "1",
                        value:       @link["max_uses"],
                        placeholder: "Unlimited",
                        class:       INPUT_FIELD)
                end
                div do
                  label(class: "block text-[10px] font-semibold text-gray-500 mb-[5px]") { plain "Link expiry" }
                  expiry_val = begin
                    @link["expires_at"].present? ? Time.parse(@link["expires_at"]).strftime("%Y-%m-%dT%H:%M") : nil
                  rescue ArgumentError, TypeError
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

          # Actions
          divider
          div(class: "px-4 pt-3 pb-4 flex items-center justify-between gap-3") do
            button(
              type:  "button",
              class: "text-[12.5px] font-medium text-gray-500 hover:text-gray-700 transition-colors cursor-pointer border-0 bg-transparent",
              data:  { action: "inline-edit#cancel" }
            ) { plain "Cancel" }
            button(
              type:  "submit",
              class: "flex items-center gap-[5px] px-[14px] py-[7px] rounded-xl text-[12.5px] font-semibold " \
                     "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0"
            ) { plain "Save settings" }
          end
        end
      end

      # ── Right preview area ────────────────────────────────────────────────────

      def preview_area
        url = @link["checkout_url"].to_s

        cl            = @link["checkout_layout"] || {}
        brand_color   = @checkout_config["brand_colour"].presence || cl["brand_color"].presence || "#3D47F5"
        saved_logo    = cl["logo_url"].to_s.presence || @checkout_config["logo_url"].to_s.presence
        default_name  = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        merchant_name = @checkout_config["display_name"].presence || cl["business_name"].presence || default_name

        sym   = CURRENCY_SYMBOLS.fetch(@link["currency"].to_s, @link["currency"].to_s)
        fixed = @link["kind"] == "fixed_amount"
        amt   = @link["amount"].to_i
        amount_display = fixed && amt > 0 ? "#{sym} #{fmt_num(amt)}" : "You choose"
        cta_text = cl["cta_text"].presence || (fixed && amt > 0 ? "Pay #{sym} #{fmt_num(amt)}" : "Pay now")
        saved_headline = cl["headline"].to_s.presence
        raw_terms      = cl["terms"]
        terms_data     = if raw_terms.is_a?(Hash) && raw_terms["enabled"]
          { label: raw_terms["label"].presence || "I agree to the Terms & Conditions",
            url:   raw_terms["url"].to_s }
        end

        div(
          class: "absolute top-5 right-0 bottom-0 overflow-y-auto",
          style: "left: 365px",
          data:  { controller: "payment-link-compose" }
        ) do
          div(class: "min-h-full pb-10 flex flex-col items-center pt-5 px-8") do
            share_pill(url)
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
              show_label:      true,
              headline:        saved_headline,
              terms:           terms_data
            )
          end
        end

        copy_script(url)
      end

      # ── Share pill ────────────────────────────────────────────────────────────

      def share_pill(url)
        preview_url = url.include?("?") ? "#{url}&preview=1" : "#{url}?preview=1"
        div(
          class: "w-full max-w-[900px] flex items-center gap-0 mb-3 " \
                 "bg-white border border-gray-200/80 rounded-2xl overflow-hidden " \
                 "shadow-[0_4px_20px_rgba(0,0,0,0.06)]"
        ) do
          div(class: "flex items-center gap-2.5 flex-1 min-w-0 px-4 py-[9px]") do
            span(class: "text-[10px] font-bold uppercase tracking-[0.1em] text-gray-300 flex-shrink-0") do
              plain "Share"
            end
            span(class: "w-px h-3 bg-gray-200 flex-shrink-0")
            a(href: preview_url, target: "_blank", rel: "noopener noreferrer",
              class: "font-mono text-[11px] text-[#3D47F5] hover:underline truncate") { plain url }
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          button(type: "button", id: "pl-copy-btn",
                 class: "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                        "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors cursor-pointer",
                 data: { url: url }) do
            render UI::Icon.new(:copy, class: "w-3.5 h-3.5")
            plain "Copy"
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          a(href: "https://wa.me/?text=#{CGI.escape("#{@link["description"].presence || "Pay here"}: #{url}")}",
            target: "_blank", rel: "noopener noreferrer",
            class: "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                   "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors no-underline") do
            span(class: "text-[13px] leading-none") { plain "💬" }
            plain "WhatsApp"
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          button(type: "button", id: "pl-qr-btn",
                 data: { url: payment_link_display_path(@link["id"]) },
                 class: "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                        "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors cursor-pointer border-0 bg-transparent") do
            render UI::Icon.new(:qr_code, class: "w-3.5 h-3.5")
            plain "QR"
          end
        end
      end

      # ── Copy / QR script ──────────────────────────────────────────────────────

      def copy_script(url)
        script(nonce: content_security_policy_nonce) do
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

      # ── Layout appearance block (merged from checkout_layout_view) ───────────

      def layout_appearance_block
        cl            = @link["checkout_layout"] || {}
        saved_color   = @checkout_config["brand_colour"].presence || cl["brand_color"].presence || "#3D47F5"
        saved_font    = cl["font_family"].to_s
        saved_name    = @checkout_config["display_name"].to_s
        saved_headline = cl["headline"].to_s
        saved_cta     = cl["cta_text"].to_s
        logo_url      = cl["logo_url"].to_s.presence || @checkout_config["logo_url"].to_s.presence
        terms         = cl["terms"] || {}
        terms_enabled = terms["enabled"] == true
        saved_label   = terms["label"].presence || "I agree to the Terms & Conditions"
        saved_url     = terms["url"].to_s

        # Visual separator + header
        div(class: "h-[3px] bg-gray-50 flex-shrink-0 mt-1")
        div(class: "flex items-center justify-between px-4 pt-3 pb-2 flex-shrink-0") do
          p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-500") { plain "Appearance" }
          span(
            class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-green-50 text-green-600",
            hidden: true,
            data: { checkout_layout_target: "savedBadge" }
          ) { plain "Saved" }
        end
        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")

        # Branding
        div(class: "px-4 pt-2 pb-3") do
          layout_section_label("Branding")
          if logo_url.present?
            div(class: "flex items-center gap-2") do
              img(src: logo_url, alt: "Logo",
                  class: "w-8 h-8 rounded-lg object-contain flex-shrink-0")
              div(class: "flex-1 min-w-0") do
                p(class: "text-[11px] font-semibold text-gray-700 truncate") { plain "Custom logo" }
                a(href: settings_path(tab: "verification"),
                  class: "text-[10px] text-[#3D47F5] hover:underline") { plain "Change in Settings →" }
              end
            end
          else
            div(class: "flex items-center gap-[7px] px-[10px] py-[8px] bg-gray-50 rounded-xl border border-dashed border-gray-200") do
              div do
                p(class: "text-[10px] font-medium text-gray-500 leading-tight") { plain "No logo uploaded" }
                a(href: settings_path(tab: "verification"),
                  class: "text-[10px] text-[#3D47F5] hover:underline leading-tight") { plain "Upload in Settings →" }
              end
            end
          end
          input(type: "hidden", value: logo_url.to_s,
                data: { checkout_layout_target: "logoUrlInput" })
        end

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")

        # Appearance — color + font
        div(class: "px-4 pt-2 pb-3") do
          layout_section_label("Color & font")
          div(class: "flex items-center gap-[6px] mb-[7px]") do
            input(
              type:  "color",
              value: saved_color,
              class: "w-7 h-7 rounded-md cursor-pointer border border-gray-200 p-0 bg-white",
              style: "appearance:none;-webkit-appearance:none;padding:1px;",
              data:  { action: "input->checkout-layout#syncColorHex" }
            )
            layout_input(value: saved_color, placeholder: "#3D47F5",
                         data: { action: "input->checkout-layout#updateBrandColor",
                                 preview_color_hex: "" })
          end
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

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")

        # Content — name + headline
        div(class: "px-4 pt-2 pb-3") do
          layout_section_label("Content")
          div(class: "flex flex-col gap-[6px]") do
            div do
              p(class: "text-[9.5px] text-gray-400 mb-[3px]") { plain "Business name (optional override)" }
              layout_input(value: saved_name, placeholder: "Your business name",
                           data: { action: "input->checkout-layout#updateBusinessName" })
            end
            div do
              p(class: "text-[9.5px] text-gray-400 mb-[3px]") { plain "Checkout headline (optional)" }
              layout_input(value: saved_headline, placeholder: "e.g. Support our fundraiser",
                           data: { action: "input->checkout-layout#updateHeadline" })
            end
          end
        end

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")

        # CTA
        div(class: "px-4 pt-2 pb-3") do
          layout_section_label("Button label")
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

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")

        # Terms
        div(class: "px-4 pt-2 pb-3") do
          layout_section_label("Terms & Conditions")
          div(class: "flex items-center justify-between mb-[7px]") do
            p(class: "text-[11px] text-gray-600") { plain "Require acceptance before payment" }
            label(class: "relative inline-flex items-center cursor-pointer") do
              input(
                type:    "checkbox",
                class:   "sr-only peer",
                checked: terms_enabled ? true : nil,
                data:    { action: "change->checkout-layout#toggleTerms", terms_toggle: "" }
              )
              span(class: "w-7 h-[15px] bg-gray-200 rounded-full peer peer-checked:bg-[#3D47F5] transition-colors") { }
              span(class: "absolute left-[2px] top-[2px] w-[11px] h-[11px] bg-white rounded-full " \
                          "transition-transform peer-checked:translate-x-[13px]") { }
            end
          end
          div(
            class: "flex flex-col gap-[5px] overflow-hidden transition-all",
            style: terms_enabled ? "" : "display:none",
            data:  { terms_fields: "" }
          ) do
            layout_input(value: saved_label, placeholder: "I agree to the Terms & Conditions",
                         data: { action: "input->checkout-layout#updateTermsLabel" })
            layout_input(value: saved_url, placeholder: "https://yoursite.com/terms",
                         data: { action: "input->checkout-layout#updateTermsUrl" })
          end
        end

        div(class: "h-px bg-gray-100 flex-shrink-0 mx-3 mb-1")

        # Save row
        div(class: "px-4 pt-3 pb-5 flex justify-end") do
          button(
            type:     "button",
            disabled: true,
            class:    "flex items-center gap-[5px] px-[14px] py-[7px] rounded-xl text-[12.5px] font-semibold " \
                      "bg-[#3D47F5] text-white transition-colors cursor-default border-0",
            style:    "opacity:0.55",
            data: {
              action:                 "click->checkout-layout#save",
              checkout_layout_target: "saveBtn"
            }
          ) { plain "Saved" }
        end
      end

      def layout_section_label(text)
        p(class: "text-[9px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain text }
      end

      def layout_input(value:, placeholder: "", data: {})
        input(
          type:        "text",
          value:       value.to_s,
          placeholder: placeholder,
          class:       "w-full text-[11.5px] text-gray-700 bg-gray-50 border border-gray-200 " \
                       "rounded-lg px-[9px] py-[6px] outline-none focus:border-[#3D47F5] " \
                       "focus:ring-1 focus:ring-[#3D47F5]/20 transition placeholder-gray-300",
          data:        data
        )
      end

      def preview_sync_script
        script(nonce: content_security_policy_nonce) do
          raw safe(<<~JS)
            (function () {
              function syncDesc(form) {
                var ta = form.querySelector('textarea[name="description"]');
                var el = document.querySelector('[data-payment-link-compose-target="pvDescription"]');
                if (ta && el) el.textContent = ta.value.trim() || 'Payment';
              }

              function syncMethods(form) {
                var checked = Array.from(
                  form.querySelectorAll('input[name="allowed_methods[]"]:checked')
                ).map(function (cb) { return cb.value; });

                document.querySelectorAll('[data-pl-method]').forEach(function (el) {
                  el.hidden = !checked.includes(el.dataset.plMethod);
                });

                // Fix separator on first visible method item
                var visible = Array.from(document.querySelectorAll('[data-pl-method]:not([hidden])'));
                visible.forEach(function (el, idx) {
                  var sep = el.querySelector('.pv-method-sep');
                  if (sep) sep.hidden = idx === 0;
                });

                // If the selected method was hidden, select the first visible one
                var openBody = document.querySelector('[data-pl-method-body]:not([hidden])');
                if (!openBody) {
                  var first = document.querySelector('[data-pl-method]:not([hidden])');
                  if (first) first.click();
                }
              }

              function syncCollect(form) {
                var any = false;
                ['collect_email', 'collect_phone', 'collect_name'].forEach(function (name) {
                  var cb = form.querySelector('input[name="' + name + '"]');
                  var el = document.querySelector('[data-pl-collect="' + name + '"]');
                  var on = cb ? cb.checked : false;
                  if (el) el.hidden = !on;
                  if (on) any = true;
                });
                var sec = document.querySelector('[data-payment-link-compose-target="pvCustomerSection"]');
                if (sec) sec.hidden = !any;
              }

              document.addEventListener('change', function (e) {
                var form = e.target.closest('[data-preview-form]');
                if (!form) return;
                if (e.target.name === 'allowed_methods[]') syncMethods(form);
                if (['collect_email', 'collect_phone', 'collect_name'].indexOf(e.target.name) !== -1) syncCollect(form);
              });

              document.addEventListener('input', function (e) {
                var form = e.target.closest('[data-preview-form]');
                if (!form) return;
                if (e.target.name === 'description') syncDesc(form);
              });
            })();
          JS
        end
      end
    end
  end
end
