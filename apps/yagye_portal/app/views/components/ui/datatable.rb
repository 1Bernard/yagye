# frozen_string_literal: true

module UI
  # Borderless column-definition table with the vanish pattern.
  #
  # Usage:
  #   render UI::Datatable.new(records: @payments, pagy: @pagy) do |t|
  #     t.header do
  #       div { "Section title" }           # left side
  #       form { ... }                      # right side (filters / actions)
  #     end
  #     t.column("Reference") { |r| r.reference }
  #     t.column("Amount", class: "text-right tabular-nums") { |r| r.formatted_amount }
  #     t.column("Status") { |r| render UI::StatusBadge.new(status: r.status) }
  #     t.actions do |r|
  #       a(href: payment_path(r), class: UI::Theme::DROPDOWN_ITEM) { "View" }
  #     end
  #   end
  class Datatable < ApplicationComponent
    include UI::Theme

    def initialize(records:, selectable: false, pagy: nil,
                   empty_message: "No records found.", empty_icon: :layers)
      @records       = records
      @selectable    = selectable
      @pagy          = pagy
      @empty_message = empty_message
      @empty_icon    = empty_icon
      @columns       = []
      @actions       = nil
      @header_block  = nil
    end

    def view_template(&block)
      vanish(&block)

      if @pagy
        div(class: TABLE_CARD) do
          card_header if @header_block
          render_table
          render UI::Pagination.new(pagy: @pagy, class: PAGINATION_TFOOT)
        end
      elsif @header_block
        div(class: TABLE_CARD) do
          card_header
          render_table
        end
      else
        div(class: TABLE_CARD) { render_table }
      end
    end

    def header(&block)
      @header_block = block
      nil
    end

    def column(name, class: nil, &renderer)
      @columns << { name: name, cls: binding.local_variable_get(:class), renderer: renderer }
      nil
    end

    def actions(&renderer)
      @actions = renderer
      nil
    end

    private

    def card_header
      div(class: "flex items-center justify-between px-5 py-3.5 border-b border-gray-100") do
        @header_block.call
      end
    end

    def render_table
      if @records.empty?
        empty_state
      else
        table(class: "w-full border-collapse",
              data_controller: (@selectable ? "datatable" : nil)) do
          thead(class: "sticky top-0 z-10") { render_header }
          tbody { render_body }
        end
      end
    end

    def empty_state
      div(class: "py-14 flex flex-col items-center justify-center gap-2 text-center") do
        div(class: "w-10 h-10 rounded-xl bg-gray-100 flex items-center justify-center mb-1") do
          span(class: "flex w-5 h-5 text-gray-400") do
            render UI::Icon.new(@empty_icon, class: "w-full h-full")
          end
        end
        p(class: TYPE_BODY_MD) { plain @empty_message }
      end
    end

    def render_header
      tr(class: TABLE_HEADER) do
        if @selectable
          th(class: TABLE_TH) do
            input(type: "checkbox", class: CHECKBOX_INPUT,
                  data: { datatable_target: "selectAll", action: "change->datatable#selectAll" })
          end
        end
        @columns.each do |col|
          th(class: "#{TABLE_TH} #{col[:cls]}") { plain col[:name] }
        end
        th(class: "#{TABLE_TH} w-10") if @actions
      end
    end

    def render_body
      @records.each do |record|
        row_attrs = { class: TABLE_ROW }
        row_attrs[:data] = { datatable_target: "row" } if @selectable

        tr(**row_attrs) do
          if @selectable
            td(class: TABLE_CELL) do
              input(type: "checkbox", class: CHECKBOX_INPUT,
                    data: { action: "change->datatable#rowToggled" })
            end
          end
          @columns.each do |col|
            td(class: "#{TABLE_CELL} #{col[:cls]}") do
              if col[:renderer]
                result = instance_exec(record, &col[:renderer])
                plain result.to_s if result.is_a?(String) || result.is_a?(Numeric)
              end
            end
          end
          action_cell(record) if @actions
        end
      end
    end

    def action_cell(record)
      td(class: "#{TABLE_CELL} text-right pr-5") do
        div(class: "relative inline-block", data_controller: "dropdown") do
          button(type: "button", class: ROWBTN,
                 data: { action: "click->dropdown#toggle" }) do
            render UI::Icon.new(:dots_vertical, class: ICON_SM)
          end
          div(class: "#{DROPDOWN_MENU} top-full mt-1 right-0", data_dropdown_target: "menu") do
            instance_exec(record, &@actions)
          end
        end
      end
    end
  end
end
