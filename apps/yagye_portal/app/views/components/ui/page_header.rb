# frozen_string_literal: true

module UI
  # Standard page title block: heading + subtitle on the left, optional action
  # slot on the right. Wrap the action in a block:
  #
  #   render UI::PageHeader.new(title: "Team", subtitle: "Manage access.") do
  #     render UI::Button.new(variant: :primary) { "Invite" }
  #   end
  class PageHeader < ApplicationComponent
    include UI::Theme

    def initialize(title:, subtitle: nil)
      @title    = title
      @subtitle = subtitle
    end

    def view_template(&block)
      div(class: "flex items-start justify-between mb-6") do
        div do
          h1(class: TYPE_DISPLAY) { plain @title }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain @subtitle } if @subtitle
        end
        div { __yield_content__(&block) } if block
      end
    end
  end
end
