# frozen_string_literal: true

module KybReviews
  class FilterView < ApplicationComponent
    include UI::Theme

    REVIEWER_OPTIONS = [
      [ "All applications", "",            :layers ],
      [ "Unassigned",       "unassigned",  :user   ],
      [ "Assigned to me",   "mine",        :user   ]
    ].freeze

    def initialize(tab: "pending", query: nil, from: nil, to: nil, reviewer: nil, view: "list")
      @tab      = tab
      @query    = query
      @from     = from
      @to       = to
      @reviewer = reviewer
      @view     = view
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE)   { plain "Filter applications" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Narrow by reviewer or submission date." }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        form(action: kyb_reviews_path, method: "get",
             class: "flex flex-col flex-1 overflow-hidden") do
          input(type: "hidden", name: "tab",  value: @tab)
          input(type: "hidden", name: "view", value: @view)
          input(type: "hidden", name: "q",    value: @query) if @query.present?

          div(class: "flex-1 overflow-y-auto") do
            # Reviewer
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Reviewer", :user, "brand")
              div(class: "mt-3 flex flex-col gap-[2px]") do
                REVIEWER_OPTIONS.each do |(lbl, val, icon)|
                  label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 cursor-pointer transition-colors -mx-2") do
                    input(type: "radio", name: "reviewer", value: val,
                          checked: (val == @reviewer.to_s || (val == "" && @reviewer.blank?)),
                          class: "w-[13px] h-[13px] accent-[#3D47F5] flex-shrink-0 cursor-pointer")
                    div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-brand") do
                      span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
                    end
                    span(class: TYPE_BODY_MD) { plain lbl }
                  end
                end
              end
            end

            # Submitted date range
            div(class: "px-6 py-5") do
              section_label("Submitted date", :calendar, "purple")
              div(class: "mt-3 grid grid-cols-2 gap-3") do
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "From" }
                  input(type: "date", name: "from", value: @from,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-gray-400")
                end
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "To" }
                  input(type: "date", name: "to", value: @to,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-gray-400")
                end
              end
            end
          end

          div(class: "flex-shrink-0 flex items-center justify-between px-6 py-4 border-t border-gray-100 bg-white") do
            a(href: kyb_reviews_path(tab: @tab, q: @query.presence),
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
