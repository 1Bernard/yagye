# frozen_string_literal: true

module Payments
  module Customers
    class ShowView < ApplicationComponent
      include UI::Theme
      include CustomerHelpers

      SEGMENT_CFG = {
        new:        { label: "New",        css: "bg-blue-50 text-blue-700 border-blue-200" },
        high_value: { label: "High-value", css: "bg-purple-50 text-purple-700 border-purple-200" },
        churned:    { label: "Churned",    css: "bg-gray-100 text-gray-500 border-gray-200" }
      }.freeze

      def initialize(customer:, stat: nil, network: nil)
        @c       = customer
        @stat    = stat
        @network = network
      end

      def view_template
        ref = @c["merchant_customer_ref"] || @c["id"]&.first(12) || "Customer"
        render Layout::Shell.new(
          active_nav:  :customers,
          title:       ref,
          breadcrumbs: [
            { label: "Customers", url: customers_path },
            { label: ref }
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
          details_card
          payments_link_card if @c["msisdn"].present?
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          kyc_card
          velocity_card if velocity_limits_for(@c["kyc_tier"])
        end
      end

      def hero_card
        tier  = { "tier_1" => 1, "tier_2" => 2, "tier_3" => 3 }.fetch(@c["kyc_tier"], 0)
        css   = tier >= 2 ? "bg-green-50 text-green-700" : tier == 1 ? "bg-amber-50 text-amber-700" : "bg-gray-100 text-gray-500"
        ref   = @c["merchant_customer_ref"] || "—"
        logo  = Payment::PROVIDER_LOGOS[@network.to_s]
        segs  = customer_segments(@stat)

        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Merchant reference" }
              p(class: "#{TYPE_TITLE} text-gray-900 font-mono") { plain ref }
              if segs.any?
                div(class: "flex items-center gap-1.5 mt-2 flex-wrap") do
                  segs.each do |seg|
                    cfg = SEGMENT_CFG[seg]
                    span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold border #{cfg[:css]}") do
                      plain cfg[:label]
                    end
                  end
                end
              end
            end
            div(class: "flex items-center gap-2 flex-shrink-0") do
              if logo
                div(class: "w-7 h-7 rounded-full bg-white border border-gray-100 flex items-center justify-center overflow-hidden p-0.5",
                    title: Payment::PROVIDERS.fetch(@network.to_s, "")) do
                  img(src: helpers.asset_path(logo), alt: @network.to_s, class: "w-full h-full object-contain")
                end
              end
              span(class: "inline-flex items-center px-2.5 py-1 rounded-full text-[12px] font-semibold #{css}") do
                plain "KYC Tier #{tier}"
              end
            end
          end

          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("ID",     @c["id"]&.first(16) || "—", mono: true)
            meta_cell("MSISDN", @c["msisdn"] || "—", mono: true)
            meta_cell("Email",  @c["email"] || "—")
          end

          if @stat && @stat[:payment_count].to_i.positive?
            div(class: "mt-4 pt-4 border-t border-gray-100 grid grid-cols-3 gap-4") do
              div do
                p(class: TYPE_CAPTION) { plain "Total spent" }
                p(class: "text-[15px] font-bold text-gray-900 tabular-nums mt-0.5") { plain format_ghs(@stat[:total_volume]) }
              end
              div do
                p(class: TYPE_CAPTION) do
                  plain "Transactions"
                  if @stat[:refunded_count].to_i.positive?
                    span(class: "ml-1 text-amber-600") { plain "(#{@stat[:refunded_count]} refunded)" }
                  end
                end
                p(class: "text-[15px] font-bold text-gray-900 tabular-nums mt-0.5") { plain @stat[:payment_count].to_s }
              end
              div do
                p(class: TYPE_CAPTION) { plain "Last payment" }
                p(class: "text-[15px] font-bold text-gray-900 mt-0.5") do
                  plain @stat[:last_payment_at] ? @stat[:last_payment_at].strftime("%d %b %Y") : "—"
                end
              end
            end
          end
        end
      end

      def details_card
        render UI::Card.new do |card|
          card.header("Customer details")
          card.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Customer ID",   @c["id"] || "—", mono: true)
              list.row("Merchant ref",  @c["merchant_customer_ref"] || "—", mono: true)
              list.row("MSISDN",        @c["msisdn"] || "—", mono: true)
              list.row("Email",         @c["email"] || "—")
              list.row("Name",          @c["name"] || "—")
              ts = @c["inserted_at"] || @c["created_at"]
              list.row("Created", ts ? Time.parse(ts).strftime("%d %b %Y at %H:%M UTC") : "—")
            end
          end
        end
      end

      def payments_link_card
        render UI::Card.new do |card|
          card.header("Payments")
          card.body do
            div(class: "flex items-center justify-between") do
              div do
                p(class: TYPE_BODY_MD) do
                  if @stat && @stat[:payment_count].to_i.positive?
                    plain "#{@stat[:payment_count]} transaction#{"s" if @stat[:payment_count] != 1} on record"
                  else
                    plain "No payments recorded yet"
                  end
                end
                if @stat && @stat[:total_volume].to_i.positive?
                  p(class: "#{TYPE_CAPTION} mt-[2px]") { plain "Total: #{format_ghs(@stat[:total_volume])}" }
                end
              end
              a(href: payments_path(q: @c["msisdn"]),
                class: "inline-flex items-center gap-[5px] px-3 h-8 border border-gray-200 rounded-[9px] " \
                       "text-[12.5px] font-medium text-gray-600 bg-white no-underline hover:border-gray-400 " \
                       "transition-colors flex-shrink-0") do
                render UI::Icon.new(:eye, class: "w-3 h-3")
                plain "View payments"
              end
            end
          end
        end
      end

      def kyc_card
        tier = { "tier_1" => 1, "tier_2" => 2, "tier_3" => 3 }.fetch(@c["kyc_tier"], 0)

        render UI::Card.new do |card|
          card.header("KYC Status")
          card.body do
            div(class: "flex flex-col gap-3") do
              [ 1, 2, 3 ].each do |t|
                done  = tier >= t
                color = done ? GREEN : SUBTLE_TEXT
                div(class: "flex items-center gap-3") do
                  div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0", style: "background:#{color}")
                  div do
                    p(class: done ? TYPE_BODY_MD : TYPE_CAPTION) { plain "Tier #{t}" }
                    p(class: TYPE_MICRO) do
                      plain case t
                      when 1 then "Basic — MSISDN collected"
                      when 2 then "Identity — name + ID verified"
                      when 3 then "Enhanced — address + liveness"
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      def velocity_card
        return unless @stat
        limits = velocity_limits_for(@c["kyc_tier"])
        return unless limits

        today_pct  = [ (@stat[:today_volume].to_f / limits[:daily]  * 100).round, 100 ].min
        month_pct  = [ (@stat[:mtd_volume].to_f   / limits[:monthly] * 100).round, 100 ].min
        bar_color  = ->(pct) { pct >= 100 ? "#DC2626" : pct >= 80 ? "#D97706" : "#059669" }

        render UI::Card.new do |card|
          card.header("Velocity (BoG limits)")
          card.body do
            div(class: "flex flex-col gap-4") do
              velocity_bar(
                label:   "Today",
                current: @stat[:today_volume],
                limit:   limits[:daily],
                pct:     today_pct,
                color:   bar_color.call(today_pct)
              )
              velocity_bar(
                label:   "This month",
                current: @stat[:mtd_volume],
                limit:   limits[:monthly],
                pct:     month_pct,
                color:   bar_color.call(month_pct)
              )
            end
          end
        end
      end

      def velocity_bar(label:, current:, limit:, pct:, color:)
        div do
          div(class: "flex items-center justify-between mb-1.5") do
            span(class: TYPE_CAPTION) { plain label }
            span(class: "text-[11.5px] font-medium text-gray-700 tabular-nums") do
              plain "#{format_ghs(current)} / #{format_ghs(limit)}"
            end
          end
          div(class: "h-2 bg-gray-100 rounded-full overflow-hidden") do
            div(class: "h-full rounded-full transition-all",
                style: "width:#{pct}%;background:#{color}")
          end
        end
      end
    end
  end
end
