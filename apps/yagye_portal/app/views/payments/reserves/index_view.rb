# frozen_string_literal: true

module Payments
  module Reserves
    class IndexView < ApplicationComponent
      include UI::Theme

      def view_template
        render Layout::Shell.new(
          active_nav: :reserves,
          title:      "Reserves",
          subtitle:   "Funds held in reserve to cover potential chargebacks and disputes"
        ) do
          render UI::PageHeader.new(
            title:    "Reserves",
            subtitle: "A portion of your settlement is held temporarily to cover chargebacks."
          )

          coming_soon_card
        end
      end

      private

      def coming_soon_card
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-16 flex flex-col items-center text-center gap-4") do
          div(class: "w-12 h-12 rounded-2xl flex items-center justify-center mb-2",
              style: "background:#{TINT_AMBER}") do
            span(class: "flex w-[22px] h-[22px]", style: "color:#{AMBER}") do
              render UI::Icon.new(:lock, class: "w-full h-full")
            end
          end

          p(class: TYPE_TITLE) { plain "Reserves — coming soon" }
          p(class: "#{TYPE_CAPTION} max-w-sm") do
            plain "Your reserve balance and release schedule will appear here once the reserves module is live. "
            plain "Reserves are calculated as a percentage of your monthly settlement volume."
          end

          div(class: "mt-4 bg-amber-50 border border-amber-100 rounded-xl px-5 py-4 text-left max-w-md") do
            p(class: "text-[12px] font-semibold text-amber-800 mb-1") { plain "How reserves work" }
            ul(class: "#{TYPE_CAPTION} text-amber-700 space-y-1 list-disc list-inside") do
              li { plain "A rolling reserve (typically 5–10%) is withheld from each settlement." }
              li { plain "Held funds are released on a 90-day rolling basis." }
              li { plain "Dispute losses are deducted from your reserve before release." }
            end
          end
        end
      end
    end
  end
end
