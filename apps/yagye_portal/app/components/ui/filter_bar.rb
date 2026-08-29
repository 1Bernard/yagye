# frozen_string_literal: true

module UI
  # Filter form with the vanish pattern — collects field definitions,
  # renders a GET form wired to the filter-form Stimulus controller.
  # Selects and date inputs auto-submit on change.
  #
  # Usage:
  #   render UI::FilterBar.new(action: payments_path) do |f|
  #     f.search_field name: "q", value: params[:q], placeholder: "Search reference..."
  #     f.select_field name: "status", label: "Status", selected: params[:status],
  #                    options: [["All", ""], ["Paid", "paid"], ["Failed", "failed"]]
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
        class: "flex flex-wrap gap-3 items-end mb-6",
        data: { controller: "filter-form", filter_form_target: "form" }
      }
      attrs[:data][:turbo_frame] = @turbo_frame if @turbo_frame

      form(**attrs) do
        @fields.each { |f| render_field(f) }
        div(class: "flex gap-2") do
          button(type: "submit", class: BTN_PRIMARY) { "Filter" }
          button(type: "button", class: BTN_SECONDARY,
                 data: { action: "click->filter-form#clear" }) { "Clear" }
        end
      end
    end

    private

    def render_field(field)
      div(class: "flex flex-col gap-1.5") do
        label(class: TEXT_LABEL) { field[:label] } if field[:label]
        case field[:type]
        when :select
          select(name: field[:name], class: "#{SELECT_FIELD} w-auto min-w-[140px]",
                 data: { action: "change->filter-form#submit" }) do
            (field[:options] || []).each do |lbl, val|
              option(value: val, selected: val.to_s == field[:selected].to_s) { lbl }
            end
          end
        when :date
          input(type: "date", name: field[:name], value: field[:value], class: DATE_FIELD,
                data: { action: "change->filter-form#submit" })
        when :search
          div(class: "relative") do
            span(class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-400") do
              render UI::Icon.new(:search, class: ICON_SM)
            end
            input(type: "search", name: field[:name], value: field[:value],
                  placeholder: field[:placeholder] || "Search...",
                  class: "#{INPUT_FIELD} pl-8 w-auto min-w-[220px]")
          end
        end
      end
    end
  end
end
