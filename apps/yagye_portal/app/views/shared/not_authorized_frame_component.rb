# frozen_string_literal: true

module Shared
  class NotAuthorizedFrameComponent < ApplicationComponent
    def initialize(frame_id:)
      @frame_id = frame_id
    end

    def view_template
      turbo_frame_tag(@frame_id) do
        div(class: "flex items-center justify-between px-7 py-5 border-b border-gray-100") do
          h2(class: "text-[15px] font-bold tracking-[-0.01em]") { plain "Not authorised" }
        end
        div(class: "px-7 py-6") do
          p(class: "text-[13.5px] text-gray-600 leading-relaxed") do
            plain "You don't have permission to perform this action."
          end
        end
      end
    end
  end
end
