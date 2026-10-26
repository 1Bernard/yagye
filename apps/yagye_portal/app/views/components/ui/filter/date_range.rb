# frozen_string_literal: true

module UI
  module Filter
    # Standardized date range selector with a sleek segmented preset bar
    # (Today, 7d, 30d, This Month, Custom...) and progressive disclosure
    # for From/To calendar inputs.
    class DateRange < ApplicationComponent
      include UI::Theme

      PRESETS = [
        [ "All time",   "all_time"   ],
        [ "Today",      "today"      ],
        [ "Last 7d",    "7d"         ],
        [ "Last 30d",   "30d"        ],
        [ "This month", "this_month" ],
        [ "Custom…",    "custom"     ]
      ].freeze

      def initialize(from: nil, to: nil, from_name: "from", to_name: "to", show_presets: true)
        @from         = from
        @to           = to
        @from_name    = from_name
        @to_name      = to_name
        @show_presets = show_presets
      end

      def view_template
        div(data: { controller: "date-preset" }, class: "space-y-3") do
          if @show_presets
            div(class: "flex p-1 bg-gray-100/75 rounded-xl gap-1") do
              PRESETS.each do |(label_text, key)|
                button(type: "button",
                       class: "flex-1 py-1.5 px-2 text-[11.5px] font-medium rounded-lg text-gray-500 " \
                              "hover:text-gray-900 transition-all cursor-pointer text-center select-none",
                       data: {
                         date_preset_target: "preset",
                         preset: key,
                         action: "click->date-preset#select"
                       }) do
                  plain label_text
                end
              end
            end
          end

          div(data: { date_preset_target: "customPanel" },
              class: "grid grid-cols-2 gap-3 pt-0.5 hidden") do
            div do
              label(class: "#{TYPE_CAPTION} block mb-1 text-gray-400 font-medium") { plain "From" }
              input(type: "date", name: @from_name, value: @from,
                    data: {
                      date_preset_target: "from",
                      action: "change->date-preset#dateChanged"
                    },
                    class: "w-full h-8.5 border border-gray-200/80 rounded-xl px-3 text-[12px] " \
                           "text-gray-700 bg-white outline-none focus:border-indigo-400 focus:ring-1 " \
                           "focus:ring-indigo-100 transition-all")
            end
            div do
              label(class: "#{TYPE_CAPTION} block mb-1 text-gray-400 font-medium") { plain "To" }
              input(type: "date", name: @to_name, value: @to,
                    data: {
                      date_preset_target: "to",
                      action: "change->date-preset#dateChanged"
                    },
                    class: "w-full h-8.5 border border-gray-200/80 rounded-xl px-3 text-[12px] " \
                           "text-gray-700 bg-white outline-none focus:border-indigo-400 focus:ring-1 " \
                           "focus:ring-indigo-100 transition-all")
            end
          end
        end
      end
    end
  end
end
