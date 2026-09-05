# frozen_string_literal: true

module Forms
  module Portal
    class Select < Superform::Rails::Components::Select
      include FieldWrapper

      def initialize(field, hint: nil, **attrs)
        @hint = hint
        super(field, **attrs)
      end

      def view_template(&)
        wrapped { super }
      end

      protected

      def field_attributes
        super.merge(class: UI::Theme::SELECT_FIELD)
      end
    end
  end
end
