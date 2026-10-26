# frozen_string_literal: true

module UI
  class Drawer
    # Pinned action footer for drawers.
    # Uses `mt-auto` and `flex-shrink-0` to guarantee pinning to the bottom of the drawer.
    # Accepts an optional `form:` ID so the submit button can live outside the form element
    # (avoiding nested <form> violations when auxiliary forms like Save Filter are rendered).
    class Footer < ApplicationComponent
      include UI::Theme

      def initialize(clear_url: nil, clear_action: nil, clear_label: "Clear all",
                     apply_label: "Apply filters", apply_type: "submit", form: nil, extra_slot: nil)
        @clear_url    = clear_url
        @clear_action = clear_action
        @clear_label  = clear_label
        @apply_label  = apply_label
        @apply_type   = apply_type
        @form         = form
        @extra_slot   = extra_slot
      end

      def view_template
        div(class: "mt-auto flex-shrink-0 sticky bottom-0 z-10 border-t border-gray-100 bg-white") do
          @extra_slot&.call

          div(class: "flex items-center justify-between px-6 py-4") do
            if @clear_url
              a(href: @clear_url,
                class: "text-[12.5px] text-gray-400 hover:text-gray-700 transition-colors no-underline") do
                plain @clear_label
              end
            elsif @clear_action
              button(type: "button",
                     data: { action: @clear_action },
                     class: "text-[12.5px] text-gray-400 hover:text-gray-700 transition-colors bg-transparent border-0 cursor-pointer p-0") do
                plain @clear_label
              end
            else
              span
            end

            btn_attrs = { type: @apply_type, class: BTN_PRIMARY }
            btn_attrs[:form] = @form if @form.present?
            button(**btn_attrs) do
              plain @apply_label
            end
          end
        end
      end
    end
  end
end
