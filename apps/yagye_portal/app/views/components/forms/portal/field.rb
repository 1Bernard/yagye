# frozen_string_literal: true

module Forms
  module Portal
    # Redefines every field helper to produce themed portal components.
    # This is the ONE place field markup is wired to UI::Theme.
    class Field < Superform::Rails::Field
      def label(**attrs, &)
        Superform::Rails::Components::Label.new(field, class: UI::Theme::TEXT_LABEL, **attrs, &)
      end

      def input(**attrs)
        Input.new(field, **attrs)
      end

      def textarea(**attrs)
        Textarea.new(field, **attrs)
      end

      def select(*options, multiple: false, **attrs, &)
        Select.new(field, options:, multiple:, **attrs, &)
      end

      def checkbox(index: nil, **attrs)
        Checkbox.new(field, index:, **attrs)
      end
    end
  end
end
