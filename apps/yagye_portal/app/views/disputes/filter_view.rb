# frozen_string_literal: true

module Disputes
  class FilterView < ApplicationComponent
    include UI::Theme

    REASONS = [
      [ "All reasons",          "",              :flag         ],
      [ "Fraud",                "fraud",         :alert_circle ],
      [ "Duplicate charge",     "duplicate",     :copy         ],
      [ "Product not received", "not_received",  :layers       ],
      [ "Unrecognised",         "unrecognised",  :help         ],
      [ "Other",                "other",         :dots         ]
    ].freeze

    def initialize(tab: "all", query: nil, reason: nil, date_from: nil, date_to: nil)
      @tab       = tab
      @query     = query
      @reason    = reason
      @date_from = date_from
      @date_to   = date_to
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE) { plain "Filter disputes" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Narrow by status, reason or date." }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        form(action: disputes_path, method: "get",
             class: "flex flex-col flex-1 overflow-hidden") do
          input(type: "hidden", name: "tab", value: @tab)
          input(type: "hidden", name: "q",   value: @query) if @query.present?

          div(class: "flex-1 overflow-y-auto") do
            # Reason
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Reason", :flag, "amber")
              div(class: "mt-3 flex flex-col gap-[2px]") do
                REASONS.each do |(lbl, val, icon)|
                  label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 cursor-pointer transition-colors -mx-2") do
                    input(type: "radio", name: "reason", value: val,
                          checked: (val == @reason.to_s || (val == "" && @reason.blank?)),
                          class: "w-[13px] h-[13px] accent-[#3D47F5] flex-shrink-0 cursor-pointer")
                    div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-amber") do
                      span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
                    end
                    span(class: TYPE_BODY_MD) { plain lbl }
                  end
                end
              end
            end

            # Date range
            div(class: "px-6 py-5") do
              section_label("Date range", :calendar, "purple")
              div(class: "mt-3 grid grid-cols-2 gap-3") do
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "From" }
                  input(type: "date", name: "from", value: @date_from,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-gray-400")
                end
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "To" }
                  input(type: "date", name: "to", value: @date_to,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-gray-400")
                end
              end
            end
          end

          div(class: "flex-shrink-0 flex items-center justify-between px-6 py-4 border-t border-gray-100 bg-white") do
            a(href: disputes_path(tab: @tab, q: @query.presence),
              class: "text-[12.5px] text-gray-400 hover:text-gray-700 transition-colors no-underline") do
              plain "Clear all"
            end
            button(type: "submit", class: BTN_PRIMARY) { plain "Apply filters" }
          end
        end
      end
    end

    private

    def section_label(text, icon, palette)
      div(class: "flex items-center gap-2") do
        div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-#{palette}") do
          span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
        end
        p(class: "text-[12px] font-semibold text-gray-700") { plain text }
      end
    end
  end
end
