# frozen_string_literal: true

module Payments
  module Reserves
    class FilterView < ApplicationComponent
      include UI::Theme

      def initialize(q: nil, from: nil, to: nil)
        @q    = q
        @from = from
        @to   = to
      end

      def view_template
        turbo_frame_tag "drawer-frame", class: "flex flex-col h-full overflow-hidden" do
          render UI::Drawer::Header.new(
            title:        "Filter holds",
            subtitle:     "Narrow by reference or date range.",
            category:     "Reserves",
            icon:         :settings,
            palette:      "brand",
            active_count: active_count
          )

          form(action: reserves_path, method: "get",
               id: "reserves-filter-form",
               class: "flex-1 overflow-y-auto") do
            # Payment reference search
            render UI::Drawer::Section.new(title: "Payment reference", icon: :search, palette: "brand", border: true) do
              div(class: "px-1") do
                label(class: "sr-only", for: "filter_q") { plain "Payment reference" }
                input(
                  type:        "text",
                  name:        "q",
                  id:          "filter_q",
                  value:       @q,
                  placeholder: "Search by merchant reference…",
                  class:       "w-full px-3 h-9 border border-gray-200 rounded-[9px] " \
                               "text-[12.5px] text-gray-700 outline-none " \
                               "focus:border-indigo-400 focus:ring-1 focus:ring-indigo-200 " \
                               "placeholder:text-gray-400 bg-white"
                )
              end
            end

            # Date range
            render UI::Drawer::Section.new(title: "Date held", icon: :calendar, palette: "brand", border: true) do
              div(class: "grid grid-cols-2 gap-3 px-1") do
                div do
                  label(class: "#{TYPE_MICRO} block mb-1.5", for: "filter_from") { plain "From" }
                  input(
                    type:  "date",
                    name:  "from",
                    id:    "filter_from",
                    value: @from,
                    class: "w-full px-3 h-9 border border-gray-200 rounded-[9px] " \
                           "text-[12.5px] text-gray-700 outline-none " \
                           "focus:border-indigo-400 focus:ring-1 focus:ring-indigo-200 bg-white"
                  )
                end
                div do
                  label(class: "#{TYPE_MICRO} block mb-1.5", for: "filter_to") { plain "To" }
                  input(
                    type:  "date",
                    name:  "to",
                    id:    "filter_to",
                    value: @to,
                    class: "w-full px-3 h-9 border border-gray-200 rounded-[9px] " \
                           "text-[12.5px] text-gray-700 outline-none " \
                           "focus:border-indigo-400 focus:ring-1 focus:ring-indigo-200 bg-white"
                  )
                end
              end
            end
          end

          # Footer actions
          div(class: "p-4 border-t border-gray-100 flex items-center gap-2.5") do
            button(
              type:  "submit",
              form:  "reserves-filter-form",
              class: BTN_PRIMARY.to_s
            ) { plain "Apply filters" }

            if active_count > 0
              a(
                href:  reserves_path,
                class: "text-[12.5px] font-medium text-gray-500 hover:text-gray-700 transition-colors no-underline"
              ) { plain "Clear all" }
            end
          end
        end
      end

      private

      def active_count
        [ @q, @from, @to ].count(&:present?)
      end
    end
  end
end
