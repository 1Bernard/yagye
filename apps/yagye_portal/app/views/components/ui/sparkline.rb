# frozen_string_literal: true

module UI
  # Tiny trend line for stat cells — pure SVG polyline, no JS overhead.
  class Sparkline < ApplicationComponent
    def initialize(values, width: 72, height: 26, color: "#3D47F5", class: nil)
      @values = values
      @width  = width
      @height = height
      @color  = color
      @class  = binding.local_variable_get(:class)
    end

    def render? = @values.size > 1

    def view_template
      svg(
        width: @width, height: @height,
        viewbox: "0 0 #{@width} #{@height}",
        class: @class
      ) do |s|
        s.polyline(points: points, fill: "none", stroke: @color, stroke_width: "1.6",
                   stroke_linecap: "round", stroke_linejoin: "round")
      end
    end

    private

    def points
      min, max = @values.minmax
      range = (max - min).zero? ? 1 : max - min
      step  = @width / (@values.size - 1).to_f
      @values.each_with_index.map do |value, index|
        x = (index * step).round(1)
        y = (@height - ((value - min) / range.to_f * @height)).round(1)
        "#{x},#{y}"
      end.join(" ")
    end
  end
end
