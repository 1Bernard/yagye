# frozen_string_literal: true

module UI
  # items: [{label: "Payments", href: payments_path}, {label: "TX-001", href: nil}]
  # Last item (or any with href: nil) renders as current page (non-linked).
  class Breadcrumb < ApplicationComponent
    include UI::Theme

    def initialize(items)
      @items = Array(items)
    end

    def view_template
      nav(class: "mb-5") do
        ol(class: "flex items-center list-none p-0 m-0 flex-wrap") do
          li(class: "flex items-center") do
            a(href: "/", class: "flex items-center text-gray-400 no-underline") do
              span(class: "flex w-[14px] h-[14px]") do
                render UI::Icon.new(:home, class: "w-full h-full")
              end
            end
          end

          @items.each_with_index do |item, i|
            li(class: "flex items-center") do
              span(class: "mx-2 text-gray-300 text-[13px] select-none") { "/" }
              if i == @items.length - 1 || item[:href].nil?
                span(class: TYPE_BODY_MD) { plain item[:label] }
              else
                a(href: item[:href], class: "text-[13px] text-gray-400 no-underline") do
                  plain item[:label]
                end
              end
            end
          end
        end
      end
    end
  end
end
