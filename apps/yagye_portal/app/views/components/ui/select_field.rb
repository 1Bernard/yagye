# frozen_string_literal: true

module UI
  class SelectField < ApplicationComponent
    include UI::Theme

    def initialize(name:, label:, options:, selected: nil, include_blank: nil, hint: nil, **attrs)
      @name         = name
      @label        = label
      @options      = options
      @selected     = selected
      @include_blank = include_blank
      @hint         = hint
      @attrs        = attrs
    end

    def view_template
      div(class: "flex flex-col gap-1.5") do
        label(class: TEXT_LABEL, for: @name) { @label }
        select(**mix({ id: @name, name: @name, class: SELECT_FIELD }, @attrs)) do
          option(value: "", disabled: true, selected: @selected.nil?) { @include_blank } if @include_blank
          @options.each do |lbl, val|
            option(value: val, selected: val.to_s == @selected.to_s) { lbl }
          end
        end
        span(class: FORM_HINT) { @hint } if @hint
      end
    end
  end
end
