# frozen_string_literal: true

module KybReviews
  class AddUboModalView < ApplicationComponent
    include UI::Theme

    def initialize(application:)
      @app = application
    end

    def view_template
      turbo_frame(id: "modal-frame") do
        div(class: MODAL_HEAD) do
          h2(class: TEXT_H2) { plain "Add beneficial owner" }
          button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end
        form(action: add_ubo_kyb_review_path(@app), method: "post") do
          div(class: MODAL_BODY) do
            div(class: "flex flex-col gap-4") do
              div do
                label(class: "#{TYPE_LABEL} block mb-1.5", for: "ubo_subject_name") { plain "Full name" }
                input(type: "text", id: "ubo_subject_name", name: "subject_name",
                      placeholder: "e.g. Kwame Mensah", class: INPUT_FIELD, required: true)
              end
              div do
                label(class: "#{TYPE_LABEL} block mb-1.5", for: "ubo_subject_dob") { plain "Date of birth" }
                input(type: "date", id: "ubo_subject_dob", name: "subject_dob",
                      class: INPUT_FIELD, required: true)
              end
              div do
                label(class: "#{TYPE_LABEL} block mb-1.5", for: "ubo_role") { plain "Role" }
                select(name: "role", id: "ubo_role", class: SELECT_FIELD) do
                  option(value: "ubo")      { plain "UBO (beneficial owner only)" }
                  option(value: "director") { plain "Director" }
                  option(value: "both")     { plain "Director + UBO" }
                end
              end
              div do
                label(class: "#{TYPE_LABEL} block mb-1.5", for: "ubo_ownership_pct") do
                  plain "Ownership %"
                end
                div(class: "relative") do
                  input(type: "number", id: "ubo_ownership_pct", name: "ownership_pct",
                        min: "0", max: "100", step: "0.01",
                        placeholder: "e.g. 25.00",
                        class: "#{INPUT_FIELD} pr-8",
                        required: true)
                  span(class: "absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 " \
                               "text-sm pointer-events-none") { plain "%" }
                end
              end
            end
          end
          div(class: MODAL_FOOT) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            button(type: "button", class: BTN_SECONDARY,
                   data: { action: "click->modal#close" }) { plain "Cancel" }
            button(type: "submit", class: BTN_PRIMARY) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add owner"
            end
          end
        end
      end
    end
  end
end
