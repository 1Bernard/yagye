# frozen_string_literal: true

module UI
  # Canonical icon + label + value row used in profile cards and settings panels.
  # Normalises the sizing that previously differed between users/show and settings.
  #
  #   render UI::DetailRow.new(icon: :calendar, label: "Joined", value: "12 Jan 2025")
  #   render UI::DetailRow.new(icon: :mail, label: "Email", value: u.email, locked: true)
  class DetailRow < ApplicationComponent
    include UI::Theme

    def initialize(icon:, label:, value:, mono: false, locked: false)
      @icon   = icon
      @label  = label
      @value  = value
      @mono   = mono
      @locked = locked
    end

    def view_template
      div(class: "flex items-center gap-3 px-6 py-[13px] border-b border-gray-50 last:border-0") do
        div(class: "w-[30px] h-[30px] rounded-[9px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[13px] h-[13px] text-gray-400") do
            render UI::Icon.new(@icon, class: "w-full h-full")
          end
        end
        span(class: "text-[12px] text-gray-400 w-28 flex-shrink-0") { plain @label }
        div(class: "flex items-center gap-2 flex-1") do
          span(class: (@mono ? TYPE_MONO : TYPE_BODY_MD)) { plain @value.to_s }
          if @locked
            span(class: "flex w-3 h-3 text-gray-300") do
              render UI::Icon.new(:lock, class: "w-full h-full")
            end
          end
        end
      end
    end
  end
end
