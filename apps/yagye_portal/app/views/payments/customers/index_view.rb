# frozen_string_literal: true

module Payments
  module Customers
    class IndexView < ApplicationComponent
      include UI::Theme
      include CustomerHelpers

      SEGMENT_CFG = {
        new:        { label: "New",        css: "bg-blue-50 text-blue-700" },
        high_value: { label: "High-value", css: "bg-purple-50 text-purple-700" },
        churned:    { label: "Churned",    css: "bg-gray-100 text-gray-500" }
      }.freeze

      VELOCITY_CFG = {
        ok:        { label: "OK",         css: "bg-green-50 text-green-700" },
        near_limit: { label: "Near limit", css: "bg-amber-50 text-amber-700" },
        at_limit:  { label: "At limit",   css: "bg-red-50 text-red-700" },
        unknown:   { label: "—",          css: "bg-gray-100 text-gray-400" }
      }.freeze

      def initialize(customers:, query: nil, stats: {}, networks: {})
        @customers = customers
        @query     = query
        @stats     = stats
        @networks  = networks
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :customers,
          title:      "Customers",
          subtitle:   "All customers who have transacted through your account"
        ) do
          render UI::PageHeader.new(
            title:    "Customers",
            subtitle: "Customers are created automatically when a payment is initiated."
          )

          customers_table
        end
      end

      private

      def customers_table
        stats      = @stats
        networks   = @networks
        seg_fn     = method(:customer_segments)
        vel_fn     = method(:velocity_status)
        fmt_ghs    = method(:format_ghs)

        render UI::Datatable.new(
          records:       @customers,
          pagy:          nil,
          empty_message: empty_msg
        ) do |t|
          t.header { toolbar }

          t.column("Customer", class: "min-w-[180px]") do |c|
            ref      = c["merchant_customer_ref"] || c["id"]&.first(12) || "—"
            msisdn   = c["msisdn"]
            s        = stats[msisdn]
            segs     = seg_fn.call(s)
            div do
              div(class: "flex items-center gap-1.5 flex-wrap") do
                p(class: "text-[13px] font-medium text-gray-900 font-mono") { plain ref }
                segs.each do |seg|
                  cfg = SEGMENT_CFG[seg]
                  span(class: "inline-flex items-center px-1.5 py-px rounded text-[10px] font-semibold #{cfg[:css]}") do
                    plain cfg[:label]
                  end
                end
              end
              p(class: "text-[11px] text-gray-400 font-mono mt-0.5") { plain(msisdn) } if msisdn
            end
          end

          t.column("Network") do |c|
            msisdn  = c["msisdn"]
            network = networks[msisdn]
            logo    = Payment::PROVIDER_LOGOS[network.to_s]
            if logo && msisdn
              div(class: "flex items-center gap-1.5") do
                div(class: "w-6 h-6 rounded-full bg-white border border-gray-100 flex items-center justify-center flex-shrink-0 overflow-hidden p-0.5") do
                  img(src: helpers.asset_path(logo), alt: network.to_s, class: "w-full h-full object-contain")
                end
                span(class: "text-[11.5px] text-gray-600") { plain Payment::PROVIDERS.fetch(network.to_s, "—") }
              end
            else
              span(class: "text-gray-400 text-[12px]") { plain "—" }
            end
          end

          t.column("KYC Tier") do |c|
            tier = { "tier_1" => 1, "tier_2" => 2, "tier_3" => 3 }.fetch(c["kyc_tier"], 0)
            css  = case tier
            when 2 then "bg-green-50 text-green-700"
            when 1 then "bg-amber-50 text-amber-700"
            else        "bg-gray-100 text-gray-500"
            end
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium #{css}") do
              plain "Tier #{tier}"
            end
          end

          t.column("Velocity") do |c|
            msisdn = c["msisdn"]
            s      = stats[msisdn]
            status = vel_fn.call(s, c["kyc_tier"])
            cfg    = VELOCITY_CFG[status]
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium #{cfg[:css]}") do
              plain cfg[:label]
            end
          end

          t.column("Total Spent", class: "text-right tabular-nums") do |c|
            msisdn = c["msisdn"]
            s      = stats[msisdn]
            if s && s[:total_volume].to_i.positive?
              span(class: "text-[13px] font-semibold text-gray-900") { plain fmt_ghs.call(s[:total_volume]) }
            else
              span(class: "text-gray-400 text-[12px]") { plain "—" }
            end
          end

          t.column("Transactions", class: "text-right tabular-nums") do |c|
            msisdn = c["msisdn"]
            s      = stats[msisdn]
            if s
              div(class: "text-right") do
                p(class: "text-[13px] font-medium text-gray-900") { plain s[:payment_count].to_s }
                if s[:refunded_count].to_i.positive?
                  p(class: "text-[11px] text-amber-600 mt-0.5") { plain "#{s[:refunded_count]} refund#{"s" if s[:refunded_count] > 1}" }
                end
              end
            else
              span(class: "text-gray-400 text-[12px]") { plain "0" }
            end
          end

          t.column("Last Payment") do |c|
            msisdn = c["msisdn"]
            s      = stats[msisdn]
            ts     = s&.dig(:last_payment_at)
            if ts
              span(class: "text-[12.5px] text-gray-700") { plain ts.strftime("%d %b %Y") }
            else
              span(class: "text-gray-400 text-[12px]") { plain "—" }
            end
          end

          t.actions do |c|
            a(href: customer_path(c["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      def toolbar
        form(action: customers_path, method: "get") do
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search by name, phone, email or ref…",
                  class: FILTER_SEARCH_INPUT)
          end
        end
      end

      def empty_msg
        @query.present? ? "No customers match your search." : "No customers yet."
      end
    end
  end
end
