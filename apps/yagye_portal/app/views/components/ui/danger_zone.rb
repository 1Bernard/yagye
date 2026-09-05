# frozen_string_literal: true

module UI
  # Standardised danger-zone card. Pass an action block for the destructive button.
  #
  #   render UI::DangerZone.new(
  #     title: "Suspend user",
  #     description: "Immediately revokes access.",
  #     icon: :archive
  #   ) do
  #     form(...) { button { "Suspend" } }
  #   end
  class DangerZone < ApplicationComponent
    include UI::Theme

    def initialize(title:, description:, icon: :archive)
      @title       = title
      @description = description
      @icon        = icon
    end

    def view_template(&block)
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Danger zone" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Irreversible actions that affect this user's access." }
        end
        div(class: "px-6 py-5") do
          div(class: "flex items-start gap-4 p-4 danger-zone-inner") do
            div(class: "w-8 h-8 rounded-[8px] flex items-center justify-center flex-shrink-0 icon-red") do
              span(class: "flex w-[13px] h-[13px]") do
                render UI::Icon.new(@icon, class: "w-full h-full")
              end
            end
            div(class: "flex-1 min-w-0") do
              p(class: "text-[13px] font-semibold text-gray-900 mb-[2px]") { plain @title }
              p(class: TYPE_CAPTION) { plain @description }
              div(class: "mt-3") { __yield_content__(&block) } if block
            end
          end
        end
      end
    end
  end
end
