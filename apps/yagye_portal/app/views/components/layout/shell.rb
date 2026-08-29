# frozen_string_literal: true

module Layout
  class Shell < ApplicationComponent
    include UI::Theme

    def initialize(active_nav:, title:, subtitle: nil, breadcrumbs: nil)
      @active_nav  = active_nav
      @title       = title
      @subtitle    = subtitle
      @breadcrumbs = breadcrumbs
    end

    def view_template
      div(class: "flex h-screen overflow-hidden bg-gray-50 font-sans") do
        render Layout::Sidebar.new(active: @active_nav)
        div(class: "flex-1 flex flex-col min-w-0 overflow-hidden") do
          render Layout::Topbar.new(title: @title, subtitle: @subtitle, breadcrumbs: @breadcrumbs)
          main(class: "flex-1 p-6 overflow-y-auto") { yield }
        end
      end

      render UI::Flash.new(flash: flash)
      drawer_shell
      modal_shell
      div(id: "sidebar-nav-tooltip")
    end

    private

    # Permanent empty Turbo Frame that any row link can target with
    # `data: { turbo_frame: "drawer-frame" }` to load a detail view.
    def drawer_shell
      div(data: { controller: "drawer", action: "keydown.esc@window->drawer#closeOnEscape" }) do
        div(class: DRAWER_OVERLAY,
            data: { drawer_target: "overlay", action: "click->drawer#close" })
        aside(class: DRAWER_PANEL, data: { drawer_target: "panel" }) do
          turbo_frame_tag("drawer-frame", data: { action: "turbo:frame-load->drawer#open" })
        end
      end
    end

    # Permanent empty Turbo Frame for modal dialogs, triggered via
    # `data: { turbo_frame: "modal-frame" }` links or buttons.
    def modal_shell
      div(class: MODAL_OVERLAY,
          data: { controller: "modal",
                  action: "click->modal#closeOnBackdrop keydown.esc@window->modal#closeOnEscape" }) do
        div(class: "#{MODAL_PANEL}", data: { modal_target: "panel" }) do
          turbo_frame_tag("modal-frame", data: { action: "turbo:frame-load->modal#open" })
        end
      end
    end
  end
end
