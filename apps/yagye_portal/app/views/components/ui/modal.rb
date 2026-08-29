# frozen_string_literal: true

module UI
  # Modal dialog shell. Renders the overlay + panel + optional header/footer.
  # Wired to modal_controller.js — include the modal shell once in Layout::Shell.
  #
  # Standalone usage (renders its own open/close chrome):
  #   render UI::Modal.new(title: "New API Key") do
  #     render Forms::ApiKeyForm.new(...)
  #   end
  #
  # Turbo Frame usage — the permanent empty frame in Layout::Shell receives
  # content via `data: { turbo_frame: "modal-frame" }` links.
  class Modal < ApplicationComponent
    include UI::Theme

    def initialize(title: nil, size: :md)
      @title = title
      @size  = size
    end

    SIZE_CLASS = {
      sm: "max-w-md",
      md: "max-w-2xl",
      lg: "max-w-4xl"
    }.freeze

    def view_template(&block)
      div(class: "#{MODAL_OVERLAY} opacity-100 pointer-events-auto",
          data: { controller: "modal", action: "click->modal#closeOnBackdrop keydown.esc@window->modal#closeOnEscape" }) do
        div(class: "w-full #{SIZE_CLASS.fetch(@size, SIZE_CLASS[:md])} bg-white border border-gray-100 " \
                   "rounded-2xl shadow-2xl max-h-[90vh] overflow-y-auto",
            data: { modal_target: "panel" }) do
          modal_header if @title
          div(class: MODAL_BODY, &block) if block
        end
      end
    end

    private

    def modal_header
      div(class: MODAL_HEAD) do
        h2(class: TEXT_H2) { @title }
        close_btn
      end
    end

    def close_btn
      button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
        render UI::Icon.new(:x, class: ICON_SM)
      end
    end
  end
end
