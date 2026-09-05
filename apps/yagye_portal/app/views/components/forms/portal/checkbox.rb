# frozen_string_literal: true

module Forms
  module Portal
    class Checkbox < Superform::Rails::Components::Checkbox
      def view_template
        div do
          label(class: "flex items-center gap-2 cursor-pointer") do
            super
            span(class: "text-[13px] text-gray-700") { field.human_attribute_name }
          end
          error_text
        end
      end

      protected

      def field_attributes
        super.merge(class: UI::Theme::CHECKBOX_INPUT)
      end

      private

      def error_text
        return unless field.invalid?

        span(class: UI::Theme::FIELD_ERROR_TEXT) { field.errors.join(", ") }
      end
    end
  end
end
