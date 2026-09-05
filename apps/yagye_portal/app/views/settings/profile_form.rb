# frozen_string_literal: true

module Settings
  class ProfileForm < Forms::Portal::Base
    def view_template
      error_summary

      div(class: "flex flex-col gap-4") do
        div(class: "grid grid-cols-2 gap-3") do
          Field(:first_name).input(required: true)
          Field(:last_name).input(required: true)
        end

        div do
          Field(:email).input(type: "email", readonly: true, disabled: true)
          p(class: "#{UI::Theme::TYPE_CAPTION} mt-1.5") do
            plain "Email changes require identity verification. Contact support to update."
          end
        end
      end

      div(class: "flex gap-[10px] justify-end mt-5") do
        render UI::Button.new(
          variant: :secondary,
          data: { action: "click->dialog#close", dialog_target_param: "edit-profile-dialog" }
        ) do
          render UI::Icon.new(:x, class: UI::Theme::ICON_SM)
          plain "Cancel"
        end
        submit("Save changes")
      end
    end
  end
end
