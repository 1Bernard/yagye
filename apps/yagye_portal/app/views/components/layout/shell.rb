# frozen_string_literal: true

module Layout
  class Shell < ApplicationComponent
    include UI::Theme

    def initialize(active_nav:, title:, subtitle: nil, breadcrumbs: nil, padded: true, show_kyb_banner: true)
      @active_nav       = active_nav
      @title            = title
      @subtitle         = subtitle
      @breadcrumbs      = breadcrumbs
      @padded           = padded
      @show_kyb_banner  = show_kyb_banner
    end

    def view_template
      div(class: "flex h-screen overflow-hidden bg-gray-50 font-sans") do
        render Layout::Sidebar.new(active: @active_nav)
        div(class: "flex-1 flex flex-col min-w-0 overflow-hidden") do
          render Layout::Topbar.new(title: @title, subtitle: @subtitle, breadcrumbs: @breadcrumbs)
          # Lazy-loaded KYB banner — fetched after page render so it never blocks load.
          # The frame stays empty if KYB is complete or user is not a merchant.
          if current_user&.merchant_user? && @show_kyb_banner
            turbo_frame_tag("kyb-banner", src: kyb_banner_path)
          end
          main(class: "flex-1 min-h-0 #{@padded ? 'p-6 overflow-y-auto' : 'overflow-hidden'}") { yield }
        end
      end

      render UI::Flash.new(flash: flash)
      drawer_shell
      modal_shell
      div(id: "sidebar-nav-tooltip")

      if current_user
        raw safe(turbo_stream_from("user_notifications_#{current_user.id}"))
        session_expiry_guard
      end
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

    def session_expiry_guard
      timeout_s = current_user.timeout_in.to_i
      div(
        data: {
          controller:                          "session-expiry",
          session_expiry_timeout_seconds_value: timeout_s,
          session_expiry_keepalive_url_value:  session_keepalive_path,
          session_expiry_sign_out_url_value:   destroy_user_session_path
        }
      ) do
        div(
          data: { session_expiry_target: "modal" },
          hidden: true,
          class: "fixed inset-0 z-[9999] flex items-center justify-center",
          style: "background:rgba(0,0,0,0.45)"
        ) do
          div(class: "bg-white rounded-2xl shadow-2xl p-8 max-w-sm w-full mx-4") do
            div(class: "flex items-center gap-3 mb-4") do
              div(class: "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0",
                  style: "background:rgba(217,119,6,0.10);border:1px solid rgba(217,119,6,0.25)") do
                span(class: "flex w-[18px] h-[18px]", style: "color:#d97706") do
                  render UI::Icon.new(:clock, class: "w-full h-full")
                end
              end
              div do
                p(class: "text-[14px] font-bold text-gray-900") { plain "Session expiring" }
                p(class: "text-[12px] text-gray-500 mt-[1px]") { plain "You'll be signed out in" }
              end
            end

            div(class: "text-[40px] font-bold tabular-nums text-center mb-5",
                style: "color:#d97706;letter-spacing:-0.02em",
                data: { session_expiry_target: "countdown" }) { plain "2:00" }

            div(class: "flex gap-3") do
              button(
                type: "button",
                class: "flex-1 py-2.5 rounded-xl text-[13px] font-semibold border border-gray-200 text-gray-700 hover:bg-gray-50 transition-colors",
                data: { action: "click->session-expiry#signOut" }
              ) { plain "Sign out" }
              button(
                type: "button",
                class: "flex-1 py-2.5 rounded-xl text-[13px] font-semibold text-white transition-colors",
                style: "background:#{BRAND}",
                data: { action: "click->session-expiry#stayLoggedIn" }
              ) { plain "Stay logged in" }
            end
          end
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
