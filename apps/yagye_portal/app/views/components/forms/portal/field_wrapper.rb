# frozen_string_literal: true

module Forms
  module Portal
    # Shared "label above control, error below" layout used by Input,
    # Textarea, and Select — mirrors the structure of UI::InputField.
    module FieldWrapper
      def wrapped(&control)
        div(class: "flex flex-col gap-1.5") do
          render field.label
          control.call
          hint_text
          error_text
        end
      end

      private

      def hint_text
        return unless @hint

        span(class: UI::Theme::FORM_HINT) { @hint }
      end

      def error_text
        return unless field.invalid?

        span(class: UI::Theme::FIELD_ERROR_TEXT) { field.errors.join(", ") }
      end
    end
  end
end
