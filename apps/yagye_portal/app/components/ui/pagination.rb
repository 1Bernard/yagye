# frozen_string_literal: true

module UI
  class Pagination < ApplicationComponent
    include UI::Theme

    def initialize(pagy:, class: nil)
      @pagy  = pagy
      @class = binding.local_variable_get(:class) || PAGINATION_STANDALONE
    end

    def render?
      @pagy.pages > 1
    end

    def view_template
      div(class: @class) do
        span(class: "text-[12.5px] text-gray-400") do
          plain "#{@pagy.from}–#{@pagy.to} of #{@pagy.count}"
        end
        div(class: PAGER) do
          nav_btn(@pagy.prev, "‹")
          @pagy.series.each { |item| series_item(item) }
          nav_btn(@pagy.next, "›")
        end
      end
    end

    private

    def series_item(item)
      return span(class: PAGER_GAP) { "…" } if item == :gap

      if item.is_a?(String)
        span(class: PAGER_BTN_ON) { item }
      else
        a(href: page_url(item), class: PAGER_BTN) { item.to_s }
      end
    end

    def nav_btn(page, label)
      if page
        a(href: page_url(page), class: PAGER_BTN) { label }
      else
        span(class: "#{PAGER_BTN} opacity-30") { label }
      end
    end

    def page_url(page)
      params = request.query_parameters.merge("page" => page)
      "#{request.path}?#{Rack::Utils.build_nested_query(params)}"
    end
  end
end
