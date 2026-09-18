# frozen_string_literal: true

module Payments
  module Customers
    class ShowView < ApplicationComponent
      include UI::Theme

      def initialize(customer:)
        @c = customer
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
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          kyc_card
        end
      end

      def hero_card
        tier  = @c["kyc_tier"].to_i
        css   = tier >= 2 ? "bg-green-50 text-green-700" : tier == 1 ? "bg-amber-50 text-amber-700" : "bg-gray-100 text-gray-500"
        ref   = @c["merchant_customer_ref"] || "—"

        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Merchant reference" }
              p(class: "#{TYPE_TITLE} text-gray-900 font-mono") { plain ref }
            end
            span(class: "inline-flex items-center px-2.5 py-1 rounded-full text-[12px] font-semibold #{css}") do
              plain "KYC Tier #{tier}"
            end
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("ID",           @c["id"]&.first(16) || "—", mono: true)
            meta_cell("MSISDN",       @c["msisdn"] || "—", mono: true)
            meta_cell("Email",        @c["email"] || "—")
          end
        end
      end

      def details_card
        render UI::Card.new do |card|
          card.header("Customer details")
          card.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Customer ID",          @c["id"] || "—", mono: true)
              list.row("Merchant ref",          @c["merchant_customer_ref"] || "—", mono: true)
              list.row("MSISDN",               @c["msisdn"] || "—", mono: true)
              list.row("Email",                @c["email"] || "—")
              list.row("First name",           @c["first_name"] || "—")
              list.row("Last name",            @c["last_name"] || "—")
              list.row("Country",              @c["country"] || "—")

              ts = @c["inserted_at"] || @c["created_at"]
              list.row("Created", ts ? Time.parse(ts).strftime("%d %b %Y at %H:%M UTC") : "—")
            end
          end
        end
      end

      def kyc_card
        tier = @c["kyc_tier"].to_i

        render UI::Card.new do |card|
          card.header("KYC Status")
          card.body do
            div(class: "flex flex-col gap-3") do
              [0, 1, 2].each do |t|
                done  = tier >= t
                color = done ? GREEN : SUBTLE_TEXT
                div(class: "flex items-center gap-3") do
                  div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0", style: "background:#{color}")
                  div do
                    p(class: done ? TYPE_BODY_MD : TYPE_CAPTION) { plain "Tier #{t}" }
                    p(class: TYPE_MICRO) do
                      plain case t
                            when 0 then "Basic — MSISDN collected"
                            when 1 then "Identity — name + ID verified"
                            when 2 then "Enhanced — address + liveness"
                            end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
