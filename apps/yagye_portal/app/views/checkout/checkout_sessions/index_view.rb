# frozen_string_literal: true

module Checkout
  module CheckoutSessions
    class IndexView < ApplicationComponent
      include UI::Theme

      STATE_COLORS = {
        "open"       => "bg-blue-50 text-blue-700",
        "processing" => "bg-amber-50 text-amber-700",
        "completed"  => "bg-green-50 text-green-700",
        "cancelled"  => "bg-gray-100 text-gray-500",
        "expired"    => "bg-gray-100 text-gray-400"
      }.freeze

      TABS = [
        { key: "all",        label: "All"        },
        { key: "open",       label: "Open"       },
        { key: "processing", label: "Processing" },
        { key: "completed",  label: "Completed"  },
        { key: "expired",    label: "Expired"    }
      ].freeze

      def initialize(sessions:, query: nil, tab: "all")
        @sessions = sessions
        @query    = query
        @tab      = tab
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :checkout_sessions,
          title:      "Checkout Sessions",
          breadcrumbs: [ { label: "Checkout Sessions" } ]
        ) do
          render UI::PageHeader.new(title: "Checkout Sessions",
                                    subtitle: "Customer checkout attempts initiated from your payment links.")
          stat_band
          tab_bar
          sessions_table
        end
      end

      private

      def tab_bar
        render UI::Tabs.new do |t|
          TABS.each do |tab|
            t.tab tab[:label],
                  href:   checkout_sessions_path(tab: tab[:key]),
                  active: @tab == tab[:key]
          end
        end
      end

      def stat_band
        completed = @sessions.count { |s| s["state"] == "completed" }
        open_ct   = @sessions.count { |s| s["state"] == "open" }
        total     = @sessions.size
        rate      = total > 0 ? (completed * 100.0 / total).round : 0

        render UI::Grid.new(columns: 4) do
          stat_cell("Total sessions",  total.to_s,      icon: :layers,       color: BRAND, tint: TINT_BRAND)
          stat_cell("Completed",       completed.to_s,  icon: :check_circle, color: GREEN, tint: TINT_GREEN)
          stat_cell("Open / Active",   open_ct.to_s,    icon: :clock,        color: TEAL,  tint: TINT_TEAL)
          stat_cell("Conversion rate", "#{rate}%",      icon: :trending_up,  color: AMBER, tint: TINT_AMBER)
        end
      end

      def sessions_table
        render UI::Datatable.new(records: @sessions,
                                 empty_message: empty_message) do |t|
          t.header { toolbar_content }

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
            plain((i + 1).to_s)
          end

          t.column("Session ID") do |s|
            a(href: checkout_session_path(s["id"]),
              class: "#{TYPE_MONO} hover:text-brand no-underline") do
              plain s["id"].to_s.first(20)
            end
          end

          t.column("State") do |s|
            cls = STATE_COLORS[s["state"]] || "bg-gray-100 text-gray-500"
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium #{cls}") do
              plain (s["state"] || "—").capitalize
            end
          end

          t.column("Total", class: "text-right tabular-nums") do |s|
            total    = s["total_amount"].to_i
            shipping = s["shipping_amount"].to_i
            currency = s["currency"] || "GHS"
            div(class: "text-right") do
              p(class: "text-[13px] font-semibold text-gray-800 tabular-nums") do
                plain "#{currency} #{"%.2f" % (total / 100.0)}"
              end
              if shipping > 0
                p(class: "#{TYPE_CAPTION} tabular-nums") do
                  plain "+ #{currency} #{"%.2f" % (shipping / 100.0)} shipping"
                end
              end
            end
          end

          t.column("Payment link") do |s|
            if s["payment_link_id"].present?
              span(class: TYPE_MONO) { plain s["payment_link_id"].to_s.first(16) }
            else
              span(class: TYPE_CAPTION) { plain "Direct" }
            end
          end

          t.column("Reference") do |s|
            ref = s["merchant_reference"]
            ref.present? ? span(class: TYPE_MONO) { plain ref } : span(class: TYPE_CAPTION) { plain "—" }
          end

          t.column("Created") do |s|
            span(class: TYPE_CAPTION) do
              plain s["inserted_at"] ? Time.parse(s["inserted_at"]).strftime("%d %b, %H:%M") : "—"
            end
          end

          t.actions do |s|
            a(href: checkout_session_path(s["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      def toolbar_content
        form(action: checkout_sessions_path, method: "get",
             data: { controller: "filter-form", filter_form_target: "form" }) do
          input(type: "hidden", name: "tab", value: @tab)
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search by session ID or reference…",
                  class: FILTER_SEARCH_INPUT)
          end
        end
      end

      def empty_message
        (@tab != "all") || @query.present? ? "No sessions match those filters." : "No checkout sessions yet. Sessions are created when customers open a payment link."
      end
    end
  end
end
