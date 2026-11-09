# frozen_string_literal: true

module UI
  # Visual "Where / And" condition builder for complex payment filtering.
  # Renders condition rows (field + operator + value) that submit as:
  #   filters[][field], filters[][op], filters[][value]
  #
  # Backed by a Stimulus controller (query-builder) for adding/removing rows.
  #
  # Usage:
  #   render UI::QueryBuilder.new(fields: PaymentFilterTranslator::ALLOWED_FIELDS,
  #                               conditions: params[:filters])
  class QueryBuilder < ApplicationComponent
    include UI::Theme

    FIELD_DISPLAY = {
      "payment_method" => { label: "Payment Method", type: :enum,
                            options: [%w[Mobile\ Money mobile_money], %w[Card card], %w[Bank\ Transfer bank_transfer]] },
      "status"         => { label: "Status", type: :enum,
                            options: [%w[Paid paid], %w[Failed failed], %w[Processing processing],
                                      %w[Initiated initiated], %w[Refunded refunded], %w[Cancelled cancelled]] },
      "provider"       => { label: "Provider", type: :enum,
                            options: [%w[MTN\ MoMo mtn_momo], %w[Telecel\ Cash telecel_cash],
                                      %w[AirtelTigo airteltigo], %w[Simulator simulator]] },
      "network"        => { label: "Network", type: :enum,
                            options: [%w[MTN MTN], %w[Telecel Telecel], %w[AirtelTigo AirtelTigo]] },
      "risk_decision"  => { label: "Risk Decision", type: :enum,
                            options: [%w[Review review], %w[Block block], %w[Pass pass]] },
      "amount"         => { label: "Amount (pesewas)", type: :integer },
      "created_at"     => { label: "Created At", type: :date }
    }.freeze

    STRING_OPS  = [%w[equals eq], %w[not\ equals neq], %w[is\ in in], %w[not\ in not_in]].freeze
    NUMERIC_OPS = [%w[equals eq], %w[≠ neq], %w[> gt], %w[≥ gte], %w[< lt], %w[≤ lte]].freeze
    DATE_OPS    = NUMERIC_OPS

    def initialize(fields: FIELD_DISPLAY, conditions: nil, merchant: false)
      @fields     = merchant ? fields.except("risk_decision") : fields
      @conditions = Array(conditions).reject { |c| c["field"].blank? }
    end

    def view_template
      div(class: "space-y-2",
          data: { controller: "query-builder" }) do
        div(data: { query_builder_target: "rows" }, class: "space-y-2") do
          if @conditions.any?
            @conditions.each_with_index { |cond, i| render_row(cond, i) }
          else
            render_row({}, 0)
          end
        end

        div(class: "flex items-center gap-3 pt-1") do
          button(type: "button",
                 class: "#{LINK_PRIMARY} text-[12.5px] inline-flex items-center gap-1.5",
                 data: { action: "click->query-builder#addRow" }) do
            span(class: "flex w-[13px] h-[13px]") do
              render UI::Icon.new(:plus, class: "w-full h-full")
            end
            plain "Add condition"
          end
          span(class: TYPE_CAPTION) { plain "— all conditions are combined with AND" }
        end
      end
    end

    private

    def render_row(cond, index)
      selected_field = cond["field"].to_s
      selected_op    = cond["op"].to_s
      current_value  = cond["value"].to_s

      div(class: "flex items-center gap-2 flex-wrap",
          data: { query_builder_target: "row" }) do
        select(name: "filters[#{index}][field]",
               class: "#{FILTER_SELECT} w-44",
               data: { action: "change->query-builder#fieldChanged" }) do
          option(value: "", disabled: true, selected: selected_field.blank?) { plain "Select field…" }
          @fields.each do |key, meta|
            option(value: key, selected: key == selected_field) { plain meta[:label] }
          end
        end

        field_meta = @fields[selected_field] || {}
        field_type = field_meta[:type] || :enum
        ops        = ops_for_type(field_type)

        select(name: "filters[#{index}][op]",
               class: "#{FILTER_SELECT} w-32",
               data: { query_builder_target: "opSelect" }) do
          ops.each do |label, val|
            option(value: val, selected: val == selected_op) { plain label }
          end
        end

        render_value_input(selected_field, field_meta, index, current_value)

        button(type: "button",
               class: BTN_ICON,
               title: "Remove condition",
               data: { action: "click->query-builder#removeRow" }) do
          span(class: "flex w-[10px] h-[10px]") do
            render UI::Icon.new(:x, class: "w-full h-full")
          end
        end
      end
    end

    def render_value_input(field_key, meta, index, current_value)
      type = meta[:type] || :enum
      name = "filters[#{index}][value]"
      css  = "#{VALUE_INPUT} flex-1"

      case type
      when :enum
        select(name: name, class: css,
               data: { query_builder_target: "valueInput" }) do
          option(value: "", disabled: true, selected: current_value.blank?) { plain "Select…" }
          (meta[:options] || []).each do |label, val|
            option(value: val, selected: val == current_value) { plain label }
          end
        end
      when :integer
        input(type: "number", name: name, value: current_value,
              placeholder: "e.g. 50000",
              class: css,
              data: { query_builder_target: "valueInput" })
      when :date
        input(type: "date", name: name, value: current_value,
              class: css,
              data: { query_builder_target: "valueInput" })
      else
        input(type: "text", name: name, value: current_value,
              placeholder: "Value…",
              class: css,
              data: { query_builder_target: "valueInput" })
      end
    end

    def ops_for_type(type)
      case type
      when :integer, :date then NUMERIC_OPS
      else STRING_OPS
      end
    end

    # Compact h-8 value input matching FILTER_SELECT / FILTER_DATE height
    VALUE_INPUT = "h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] text-gray-700 " \
                  "bg-white outline-none focus:border-gray-400 transition-colors min-w-0"
  end
end
