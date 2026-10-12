# frozen_string_literal: true

module UI
  class InputField < ApplicationComponent
    include UI::Theme

    def initialize(name:, label:, id: nil, type: "text", value: nil, placeholder: nil,
                   required: false, hint: nil, error: nil,
                   icon: nil, toggle_visibility: false, suppress_label: false, **attrs)
      @name              = name
      @id                = id || name
      @label             = label
      @type              = type
      @value             = value
      @placeholder       = placeholder
      @required          = required
      @hint              = hint
      @error             = error
      @icon              = icon
      @toggle_visibility = toggle_visibility
      @suppress_label    = suppress_label
      @attrs             = attrs
    end

    def view_template
      div(class: "flex flex-col gap-1.5") do
        label(class: TEXT_LABEL, for: @id) { plain @label } unless @suppress_label
        input_wrapper
        span(class: FORM_HINT) { plain @hint } if @hint
        span(class: FIELD_ERROR_TEXT) { plain @error } if @error
      end
    end

    private

    def input_wrapper
      if @icon || @toggle_visibility
        wrapper_attrs = { class: "relative" }
        wrapper_attrs[:data] = { controller: "password-visibility" } if @toggle_visibility

        div(**wrapper_attrs) do
          if @icon
            div(class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-400") do
              render UI::Icon.new(@icon, class: "w-4 h-4")
            end
          end
          render_input(data: @toggle_visibility ? { password_visibility_target: "input" } : {})
          visibility_toggle if @toggle_visibility
        end
      else
        render_input
      end
    end

    def render_input(extra = {})
      merged_data = (extra[:data] || {}).merge(@attrs[:data] || {})
      base = { id: @id, name: @name, type: @type, value: @value,
               placeholder: @placeholder, required: @required, class: input_class }
      base[:data] = merged_data unless merged_data.empty?
      input(**mix(base, @attrs.except(:data), extra.except(:data)))
    end

    def visibility_toggle
      button(type: "button",
             class: "absolute inset-y-0 right-0 flex items-center px-3 text-gray-400 hover:text-gray-600 transition-colors",
             data: { action: "click->password-visibility#toggle" },
             aria: { label: "Toggle password visibility" }) do
        span(hidden: true, data: { password_visibility_target: "showIcon" }) do
          render UI::Icon.new(:eye, class: "w-[15px] h-[15px]")
        end
        span(data: { password_visibility_target: "hideIcon" }) do
          render UI::Icon.new(:eye_off, class: "w-[15px] h-[15px]")
        end
      end
    end

    def input_class
      base = @error ? "#{INPUT_FIELD} border-red-400 focus:border-red-400" : INPUT_FIELD
      base += " pl-9"  if @icon
      base += " pr-10" if @toggle_visibility
      base
    end
  end
end
