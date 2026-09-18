# frozen_string_literal: true

module Checkout
  class PaymentLinksFilterView < ApplicationComponent
    include UI::Theme

    STATUS_OPTIONS = [
      [ "All links",   "",      :layers       ],
      [ "Active",      "true",  :check_circle ],
      [ "Inactive",    "false", :alert_circle ]
    ].freeze

    def initialize(query: nil, active_filter: nil, view: nil)
      @query         = query
      @active_filter = active_filter
      @view          = view
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE)   { plain "Filter links" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Narrow by link status." }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        form(action: payment_links_path, method: "get",
             class: "flex flex-col flex-1 overflow-hidden") do
          input(type: "hidden", name: "q",    value: @query)    if @query.present?
          input(type: "hidden", name: "view", value: @view)     if @view.present?

          div(class: "flex-1 overflow-y-auto") do
            div(class: "px-6 py-5") do
              section_label("Status", :layers, "brand")
              div(class: "mt-3 flex flex-col gap-[2px]") do
                STATUS_OPTIONS.each do |(lbl, val, icon)|
                  label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 cursor-pointer transition-colors -mx-2") do
                    input(type: "radio", name: "active", value: val,
                          checked: (val == @active_filter.to_s || (val == "" && @active_filter.blank?)),
                          class: "w-[13px] h-[13px] accent-[#3D47F5] flex-shrink-0 cursor-pointer")
                    div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-brand") do
                      span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
                    end
                    span(class: TYPE_BODY_MD) { plain lbl }
                  end
                end
              end
            end
          end

          div(class: "flex-shrink-0 flex items-center justify-between px-6 py-4 border-t border-gray-100 bg-white") do
            a(href: payment_links_path(q: @query.presence, view: @view.presence),
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
