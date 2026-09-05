# frozen_string_literal: true

module UI
  # Compact filter form for use in table toolbars.
  # Fields auto-submit on change; search submits on Enter.
  #
  # Usage (inside t.header or standalone):
  #   render UI::FilterBar.new(action: payments_path) do |f|
  #     f.search_field name: "q", value: params[:q], placeholder: "Search reference..."
  #     f.select_field name: "status", label: "Status", selected: params[:status],
  #                    options: [["All statuses", ""], ["Paid", "paid"], ["Failed", "failed"]]
  #     f.date_field   name: "from", label: "From", value: params[:from]
  #   end
  class FilterBar < ApplicationComponent
    include UI::Theme

    def initialize(action:, turbo_frame: nil)
      @action      = action
      @turbo_frame = turbo_frame
      @fields      = []
    end

    def search_field(**opts) = @fields << opts.merge(type: :search)
    def select_field(**opts) = @fields << opts.merge(type: :select)
    def date_field(**opts)   = @fields << opts.merge(type: :date)

    def view_template(&block)
      vanish(&block) if block

      attrs = {
        action: @action,
        method: :get,
        class: "flex items-center gap-2",
        data: { controller: "filter-form", filter_form_target: "form" }
      }
      attrs[:data][:turbo_frame] = @turbo_frame if @turbo_frame

      form(**attrs) do
        @fields.each { |f| render_field(f) }
        button(type: "button", class: FILTER_CLEAR_LINK,
               data: { action: "click->filter-form#clear" }) { plain "Clear" }
      end
    end

    private

    def render_field(field)
      case field[:type]
      when :search
        div(class: FILTER_SEARCH_WRAP) do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search", name: field[:name], value: field[:value],
                placeholder: field[:placeholder] || "Search…",
                class: FILTER_SEARCH_INPUT)
        end
      when :select
        select(name: field[:name], class: FILTER_SELECT,
               data: { action: "change->filter-form#submit" }) do
          (field[:options] || []).each do |lbl, val|
            option(value: val, selected: val.to_s == field[:selected].to_s) { plain lbl }
          end
        end
      when :date
        input(type: "date", name: field[:name], value: field[:value],
              class: FILTER_DATE,
              data: { action: "change->filter-form#submit" })
      end
    end
  end
end
