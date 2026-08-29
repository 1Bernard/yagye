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
      nav(style: "margin-bottom:20px") do
        ol(style: "display:flex;align-items:center;list-style:none;padding:0;margin:0;flex-wrap:wrap;gap:0") do
          li(style: "display:flex;align-items:center") do
            a(href: "/",
              style: "display:flex;align-items:center;color:#9ca3af;text-decoration:none") do
              span(style: "display:flex;width:14px;height:14px") do
                render UI::Icon.new(:home, class: "w-full h-full")
              end
            end
          end

          @items.each_with_index do |item, i|
            li(style: "display:flex;align-items:center") do
              span(style: "margin:0 8px;color:#d1d5db;font-size:13px;user-select:none") { "/" }
              if i == @items.length - 1 || item[:href].nil?
                span(style: "font-size:13px;color:#374151;font-weight:500") { plain item[:label] }
              else
                a(href: item[:href],
                  style: "font-size:13px;color:#9ca3af;text-decoration:none") do
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
