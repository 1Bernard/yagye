# frozen_string_literal: true

module Forms
  module Portal
    class Input < Superform::Rails::Components::Input
      include FieldWrapper

      def initialize(field, hint: nil, **attrs)
        @hint = hint
        super(field, **attrs)
      end

      def view_template
        wrapped { super }
      end

      protected

      def field_attributes
        base  = UI::Theme::INPUT_FIELD
        klass = field.invalid? ? "#{base} border-red-400 focus:border-red-400" : base
        super.merge(class: klass)
      end
    end
  end
end
