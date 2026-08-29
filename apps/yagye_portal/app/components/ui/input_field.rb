# frozen_string_literal: true

module UI
  class InputField < ApplicationComponent
    include UI::Theme

    def initialize(name:, label:, type: "text", value: nil, placeholder: nil,
                   required: false, hint: nil, error: nil, **attrs)
      @name        = name
      @label       = label
      @type        = type
      @value       = value
      @placeholder = placeholder
      @required    = required
      @hint        = hint
      @error       = error
      @attrs       = attrs
    end

    def view_template
      div(class: "flex flex-col gap-1.5") do
        label(class: TEXT_LABEL, for: @name) { @label }
        input(**mix(
          {
            id: @name, name: @name, type: @type, value: @value,
            placeholder: @placeholder, required: @required,
            class: input_class
          },
          @attrs
        ))
        span(class: FORM_HINT) { @hint } if @hint
        span(class: FIELD_ERROR_TEXT) { @error } if @error
      end
    end

    private

    def input_class
      @error ? "#{INPUT_FIELD} border-red-400 focus:border-red-400" : INPUT_FIELD
    end
  end
end
