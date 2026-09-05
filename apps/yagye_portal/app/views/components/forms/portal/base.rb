# frozen_string_literal: true

module Forms
  module Portal
    # Base for every portal form. Never instantiated directly — subclass it.
    #
    # Usage:
    #   class Settings::ProfileForm < Forms::Portal::Base
    #     def view_template
    #       error_summary
    #       div(class: "space-y-4") do
    #         Field(:first_name).input(required: true)
    #         Field(:last_name).input(required: true)
    #       end
    #       submit("Save changes")
    #     end
    #   end
    #
    # In the view: render Settings::ProfileForm.new(@current_user, url: settings_profile_path)
    class Base < Forms::Base
      include UI::Theme

      Field = Portal::Field

      def submit(value = submit_value, **attrs)
        render UI::Button.new(variant: :primary, type: "submit", **attrs) { plain value }
      end

      def error_summary
        return unless model.errors.any?

        count = model.errors.count
        div(class: "rounded-xl border border-red-200 bg-red-50 px-4 py-3 mb-4") do
          p(class: "text-[13px] font-semibold text-red-700 mb-1") do
            plain "#{count} #{count == 1 ? 'error' : 'errors'} prevented this from being saved"
          end
          ul(class: "list-disc list-inside space-y-0.5") do
            model.errors.each do |error|
              li(class: "text-[12.5px] text-red-600") { plain error.full_message }
            end
          end
        end
      end
    end
  end
end
