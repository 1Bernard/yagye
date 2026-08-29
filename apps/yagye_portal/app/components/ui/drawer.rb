# frozen_string_literal: true

module UI
  # Slide-over drawer shell. Wraps content in the right-side panel.
  # Wired to drawer_controller.js — include once in Layout::Shell.
  #
  # Used directly for one-off drawers:
  #   render UI::Drawer.new(title: "Payment Details") do
  #     render Payments::DetailComponent.new(payment: @payment)
  #   end
  #
  # Or used as a Turbo Frame shell — a permanent empty frame in
  # Layout::Shell receives content via row links with
  # `data: { turbo_frame: "drawer-frame" }`.
  class Drawer < ApplicationComponent
    include UI::Theme

    def initialize(title: nil)
      @title = title
    end

    def view_template(&block)
      div(class: "relative z-50") do
        div(class: DRAWER_OVERLAY, data: { drawer_target: "overlay", action: "click->drawer#close" })
        aside(class: DRAWER_PANEL, data: { drawer_target: "panel" }) do
          drawer_header if @title
          div(class: "p-7", &block) if block
        end
      end
    end

    private

    def drawer_header
      div(class: DRAWER_HEAD) do
        h2(class: TEXT_H2) { @title }
        button(type: "button", class: XBTN, data: { action: "click->drawer#close" }) do
          render UI::Icon.new(:x, class: ICON_SM)
        end
      end
    end
  end
end
