# frozen_string_literal: true

module UI
  # Submit button with loading state via loading-button Stimulus controller.
  # full_width: true spans the card (auth forms); false sizes to content (modal footers).
  class SubmitButton < ApplicationComponent
    include UI::Theme

    def initialize(label:, loading_label: nil, full_width: true, **attrs)
      @label         = label
      @loading_label = loading_label
      @full_width    = full_width
      @attrs         = attrs
    end

    def view_template
      base_class = @full_width ? "#{BTN_PRIMARY} w-full justify-center py-3" : "#{BTN_PRIMARY} justify-center"
      button(
        **mix(
          {
            type: "submit",
            class: base_class,
            data: {
              controller: "loading-button",
              action: "click->loading-button#start",
              loading_button_loading_text_value: @loading_label
            }
          },
          @attrs
        )
      ) do
        render UI::Icon.new(:spinner, class: "w-4 h-4 animate-spin hidden",
                                      data: { loading_button_target: "spinner" })
        span(data: { loading_button_target: "label" }) { @label }
      end
    end
  end
end
