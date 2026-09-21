# frozen_string_literal: true

module Checkout
  module CheckoutSessions
    class ShowView < ApplicationComponent
      include UI::Theme

      KIND_ICONS = {
        "item"     => :package,
        "shipping" => :truck,
        "tax"      => :percent,
        "discount" => :tag
      }.freeze

      KIND_LABELS = {
        "item"     => "Item",
        "shipping" => "Shipping",
        "tax"      => "Tax",
        "discount" => "Discount"
      }.freeze

      def initialize(session:)
        @s = session
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :checkout_sessions,
          title:      @s["id"].to_s.first(20),
          breadcrumbs: [
            { label: "Checkout Sessions", url: checkout_sessions_path },
            { label: @s["id"].to_s.first(20) }
          ]
        ) do
          render UI::Grid.new(columns: :sidebar) do
            left_column
            right_column
          end
        end
      end

      private

      def left_column
        div(class: "flex flex-col gap-5") do
          hero_card
          line_items_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          payment_card if @s["payment_id"].present?
          session_details_card
          collection_card
        end
      end

      # ── Hero ─────────────────────────────────────────────────────────────────

      def hero_card
        currency = @s["currency"] || "GHS"
        total    = @s["total_amount"].to_i
        shipping = @s["shipping_amount"].to_i

        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Session total" }
              p(class: "#{TYPE_AMOUNT} text-gray-900") do
                plain "#{currency} #{"%.2f" % (total / 100.0)}"
              end
              if shipping > 0
                p(class: "#{TYPE_CAPTION} mt-1") do
                  plain "incl. #{currency} #{"%.2f" % (shipping / 100.0)} shipping"
                end
              end
            end
            state_pill(@s["state"])
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Mode",     @s["mode"]&.capitalize || "—")
            meta_cell("Created",  @s["inserted_at"] ? Time.parse(@s["inserted_at"]).strftime("%d %b %Y") : "—")
            meta_cell("Expires",  @s["expires_at"]  ? Time.parse(@s["expires_at"]).strftime("%d %b %Y") : "No expiry")
          end
        end
      end

      # ── Line items ───────────────────────────────────────────────────────────

      def line_items_card
        items    = Array(@s["line_items"]).sort_by { |i| i["position"].to_i }
        currency = @s["currency"] || "GHS"

        render UI::Card.new do |c|
          c.header("Line items")
          c.body(padding: false) do
            if items.empty?
              div(class: "px-6 py-8 text-center") do
                p(class: TYPE_CAPTION) { plain "No line items on this session." }
              end
            else
              table(class: "w-full text-[12.5px]") do
                thead do
                  tr(class: "border-b border-gray-100") do
                    th(class: "text-left px-6 py-3 #{TYPE_CAPTION} font-semibold") { plain "Description" }
                    th(class: "text-center px-4 py-3 #{TYPE_CAPTION} font-semibold") { plain "Type" }
                    th(class: "text-right px-4 py-3 #{TYPE_CAPTION} font-semibold") { plain "Qty" }
                    th(class: "text-right px-6 py-3 #{TYPE_CAPTION} font-semibold") { plain "Amount" }
                  end
                end
                tbody do
                  items.each do |item|
                    kind   = item["kind"] || "item"
                    amount = item["total_amount"] || (item["unit_amount"].to_i * item["quantity"].to_f).round
                    tr(class: "border-b border-gray-50 last:border-0") do
                      td(class: "px-6 py-3") do
                        div(class: "flex items-center gap-2") do
                          if item["image_url"].present?
                            img(src: item["image_url"], alt: "",
                                class: "w-8 h-8 rounded-lg object-cover flex-shrink-0")
                          end
                          p(class: TYPE_BODY_MD) { plain item["description"] || "—" }
                        end
                      end
                      td(class: "px-4 py-3 text-center") do
                        kind_chip(kind)
                      end
                      td(class: "px-4 py-3 text-right #{TYPE_CAPTION} tabular-nums") do
                        qty = item["quantity"].to_f
                        plain qty % 1 == 0 ? qty.to_i.to_s : "%.2f" % qty
                      end
                      td(class: "px-6 py-3 text-right font-semibold text-gray-800 tabular-nums") do
                        plain "#{currency} #{"%.2f" % (amount / 100.0)}"
                      end
                    end
                  end
                end
              end

              # Totals summary
              div(class: "border-t border-gray-100 px-6 py-4 space-y-[3px]") do
                totals_row("Subtotal", "#{currency} #{"%.2f" % (@s["subtotal_amount"].to_i / 100.0)}")
                totals_row("Tax",      "#{currency} #{"%.2f" % (@s["tax_amount"].to_i / 100.0)}")      if @s["tax_amount"].to_i > 0
                totals_row("Shipping", "#{currency} #{"%.2f" % (@s["shipping_amount"].to_i / 100.0)}") if @s["shipping_amount"].to_i > 0
                totals_row("Discount", "- #{currency} #{"%.2f" % (@s["discount_amount"].to_i / 100.0)}") if @s["discount_amount"].to_i > 0
                div(class: "flex justify-between pt-2 border-t border-gray-100 mt-1") do
                  p(class: "text-[12px] font-bold text-gray-900") { plain "Total" }
                  p(class: "text-[13px] font-bold text-gray-900 tabular-nums") do
                    plain "#{currency} #{"%.2f" % (@s["total_amount"].to_i / 100.0)}"
                  end
                end
              end
            end
          end
        end
      end

      # ── Payment ───────────────────────────────────────────────────────────────

      def payment_card
        render UI::Card.new do |c|
          c.header("Payment")
          c.body do
            div(class: "flex items-center justify-between") do
              div(class: "flex items-center gap-3") do
                div(class: "w-8 h-8 rounded-xl bg-green-50 flex items-center justify-center flex-shrink-0") do
                  span(class: "flex w-4 h-4 text-green-600") do
                    render UI::Icon.new(:check_circle, class: "w-full h-full")
                  end
                end
                div do
                  p(class: TYPE_BODY_MD) { plain "Payment captured" }
                  p(class: TYPE_MONO) { plain @s["payment_id"] }
                end
              end
              a(href: payment_path(@s["payment_id"]),
                class: "text-[12px] text-[#3D47F5] font-medium hover:underline no-underline") do
                plain "View →"
              end
            end
          end
        end
      end

      # ── Session details ───────────────────────────────────────────────────────

      def session_details_card
        render UI::Card.new do |c|
          c.header("Session details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Session ID",     @s["id"], mono: true)
              list.row("Mode",           @s["mode"]&.capitalize || "—")
              list.row("Status")         { state_pill(@s["state"]) }
              list.row("Currency",       @s["currency"] || "—")
              list.row("Reference",      @s["merchant_reference"].presence || "—", mono: true)
              list.row("Payment link")   { payment_link_ref }
              list.row("Completed at")   { plain @s["completed_at"] ? Time.parse(@s["completed_at"]).strftime("%d %b %Y at %H:%M UTC") : "—" }
              list.row("Expires at")     { plain @s["expires_at"] ? Time.parse(@s["expires_at"]).strftime("%d %b %Y at %H:%M UTC") : "No expiry" }
              list.row("Created")        { plain @s["inserted_at"] ? Time.parse(@s["inserted_at"]).strftime("%d %b %Y at %H:%M UTC") : "—" }
            end
          end
        end
      end

      # ── Collection settings ───────────────────────────────────────────────────

      def collection_card
        render UI::Card.new do |c|
          c.header("Collected from customer")
          c.body do
            div(class: "flex flex-wrap gap-2") do
              collection_chip("Email",   @s["collect_email"])
              collection_chip("Phone",   @s["collect_phone"])
              collection_chip("Name",    @s["collect_name"])
            end
            if Array(@s["allowed_methods"]).any?
              div(class: "mt-4") do
                p(class: "#{TYPE_CAPTION} mb-2") { plain "Payment methods" }
                div(class: "flex flex-wrap gap-2") do
                  Array(@s["allowed_methods"]).each do |m|
                    span(class: "px-2 py-1 bg-gray-100 rounded-lg text-[11.5px] font-medium text-gray-600") do
                      plain m.to_s.tr("_", " ").capitalize
                    end
                  end
                end
              end
            end
          end
        end
      end

      # ── Helpers ──────────────────────────────────────────────────────────────

      def state_pill(state)
        render UI::StatusBadge.new(status: state)
      end

      def kind_chip(kind)
        colors = {
          "item"     => "bg-blue-50 text-blue-700",
          "shipping" => "bg-purple-50 text-purple-700",
          "tax"      => "bg-amber-50 text-amber-700",
          "discount" => "bg-green-50 text-green-700"
        }
        cls = colors[kind] || "bg-gray-100 text-gray-500"
        span(class: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10.5px] font-medium #{cls}") do
          if (icon = KIND_ICONS[kind])
            span(class: "flex w-[10px] h-[10px]") { render UI::Icon.new(icon, class: "w-full h-full") }
          end
          plain KIND_LABELS[kind] || kind.capitalize
        end
      end

      def collection_chip(label, active)
        cls = active ? "bg-green-50 text-green-700" : "bg-gray-100 text-gray-400"
        span(class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11.5px] font-medium #{cls}") do
          plain active ? "✓ #{label}" : "— #{label}"
        end
      end

      def payment_link_ref
        if @s["payment_link_id"].present?
          span(class: TYPE_MONO) { plain @s["payment_link_id"] }
        else
          span(class: TYPE_CAPTION) { plain "None (direct session)" }
        end
      end

      def totals_row(label, value)
        div(class: "flex justify-between") do
          p(class: "text-[12px] text-gray-500") { plain label }
          p(class: "text-[12.5px] text-gray-700 tabular-nums") { plain value }
        end
      end

      def meta_cell(label, value)
        div(class: "bg-gray-50 px-5 py-4") do
          p(class: "text-[10.5px] text-gray-400 font-semibold uppercase tracking-wide mb-[3px]") { plain label }
          p(class: "text-[13px] font-medium text-gray-800") { plain value }
        end
      end
    end
  end
end
