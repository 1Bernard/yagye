# frozen_string_literal: true

module UI
  module Chart
    # Universal ECharts component — rendered by the ui--chart Stimulus controller.
    # Subclasses supply only `chart_type` ("line", "bar", "doughnut").
    #
    # Single-series: pass `data:` + optional `dataset_label:`.
    # Multi-series:  pass `series:` (array of {name:, data:, area:}).
    # `colors:` overrides the CSS-token palette with exact hex values in series order.
    # `ring:` draws a neutral full-circle track under a doughnut.
    # `selected_index:` pre-selects one pie slice.
    class Base < ApplicationComponent
      include UI::Theme

      def initialize(labels:, data: nil, dataset_label: "", series: nil, format: :number,
                     stacked: false, area: false, center_label: nil, center_sublabel: nil,
                     colors: nil, ring: false, selected_index: nil, height: 256)
        @labels          = labels
        @data            = data
        @dataset_label   = dataset_label
        @series          = series
        @format          = format
        @stacked         = stacked
        @area            = area
        @center_label    = center_label
        @center_sublabel = center_sublabel
        @colors          = colors
        @ring            = ring
        @selected_index  = selected_index
        @height          = height
      end

      def view_template
        return empty_state if @labels.empty?

        div(class: "relative group", style: "height:#{@height}px", **stimulus_attrs) do
          div(class: "w-full h-full", data_ui__chart_target: "container")
          download_button
        end
        accessible_summary
      end

      private

      def chart_type
        raise NotImplementedError, "#{self.class} must define #chart_type"
      end

      def stimulus_attrs
        {
          data_controller:                      "ui--chart",
          data_ui__chart_type_value:            chart_type,
          data_ui__chart_labels_value:          @labels.to_json,
          data_ui__chart_data_value:            (@data || []).to_json,
          data_ui__chart_formatted_data_value:  formatted_data.to_json,
          data_ui__chart_series_value:          formatted_series.to_json,
          data_ui__chart_dataset_label_value:   @dataset_label,
          data_ui__chart_currency_unit_value:   @format == :currency ? number_to_currency(1).gsub(/[\d.,\s]/, "").strip : "",
          data_ui__chart_stacked_value:         @stacked,
          data_ui__chart_area_value:            @area,
          data_ui__chart_center_label_value:    @center_label.to_s,
          data_ui__chart_center_sublabel_value: @center_sublabel.to_s,
          data_ui__chart_colors_value:          (@colors || []).to_json,
          data_ui__chart_ring_value:            @ring,
          data_ui__chart_selected_index_value:  @selected_index || -1
        }
      end

      def formatted_data
        (@data || []).map { |value| format_value(value) }
      end

      def formatted_series
        (@series || []).map { |s| s.merge(formatted: s[:data].map { |v| format_value(v) }) }
      end

      def format_value(value)
        @format == :currency ? number_to_currency(value) : number_with_delimiter(value)
      end

      def accessible_summary
        ul(class: SR_ONLY) do
          if @series
            @series.each { |s| s[:data].each_with_index { |v, i| li { "#{s[:name]} — #{@labels[i]}: #{v}" } } }
          else
            @labels.each_with_index { |label, i| li { "#{label}: #{formatted_data[i]}" } }
          end
        end
      end

      def download_button
        button(type: "button", class: CHART_DOWNLOAD_BTN,
               data_action: "click->ui--chart#downloadImage",
               aria_label: "Download chart") do
          render UI::Icon.new(:download, class: ICON_SM)
        end
      end

      def empty_state
        div(class: CHART_EMPTY_STATE) { plain "No data available" }
      end
    end
  end
end
