# frozen_string_literal: true

module Developers
  class ProvidersIndexView < ApplicationComponent
    include UI::Theme

    STATUS_MAP = {
      "active"   => STATUS_SUCCESS,
      "paused"   => STATUS_WARNING,
      "disabled" => STATUS_NEUTRAL
    }.freeze

    def initialize(connections:, psps:)
      @connections = connections
      @psps        = psps
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :psp_providers,
        title:       "PSP Providers",
        breadcrumbs: [{ label: "PSP Providers" }]
      ) do
        render UI::PageHeader.new(
          title:    "PSP Providers",
          subtitle: "Connect external payment providers for intelligent routing and failover."
        ) do
          render UI::Button.new(variant: :primary,
                                href: new_developers_provider_path,
                                data: { turbo_frame: "drawer-frame" }) do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "Add PSP"
          end
        end

        stat_band
        providers_section
      end
    end

    private

    def stat_band
      total    = @connections.size
      active   = @connections.count { |c| c["status"] == "active" }
      modes    = @connections.map { |c| c["mode"] }.compact.uniq.size
      live_cnt = @connections.count { |c| c["mode"] == "live" && c["status"] == "active" }

      render UI::Grid.new(columns: 4) do
        stat_cell("Connected",      total.to_s,    icon: :layers,       color: BRAND,  tint: TINT_BRAND)
        stat_cell("Active",         active.to_s,   icon: :check_circle, color: GREEN,  tint: TINT_GREEN)
        stat_cell("Modes",          modes.to_s,    icon: :globe,        color: AMBER,  tint: TINT_AMBER)
        stat_cell("Live active",    live_cnt.to_s, icon: :bank,         color: GREEN,  tint: TINT_GREEN)
      end
    end

    def providers_section
      if @connections.empty?
        empty_state
      else
        div(class: "flex flex-col gap-3 mt-2") do
          @connections.sort_by { |c| c["priority"].to_i }.each { |c| provider_card(c) }
        end
      end
    end

    def provider_card(conn)
      status     = conn["status"] || "active"
      psp_info   = @psps.find { |p| p[:code] == conn["provider_code"] } || {}
      label      = psp_info[:label] || conn["provider_name"] || conn["provider_code"].to_s.titleize
      methods    = Array(conn["enabled_methods"])
      priority   = conn["priority"].to_i

      div(class: "#{SURFACE_CARD} flex items-center gap-4 px-5 py-4") do
        # Priority badge
        div(class: "w-8 h-8 rounded-xl bg-gray-100 flex items-center justify-center flex-shrink-0") do
          span(class: "text-[12px] font-bold text-gray-500") { plain priority.to_s }
        end

        # PSP info
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 mb-[3px]") do
            p(class: "text-[14px] font-semibold text-gray-900") { plain label }
            status_badge(status)
          end
          div(class: "flex items-center gap-3 flex-wrap") do
            mode_tag(conn["mode"])
            methods.each { |m| method_tag(m) } if methods.any?
          end
        end

        # Actions
        div(class: "flex items-center gap-2 flex-shrink-0") do
          render UI::Button.new(
            variant: :secondary,
            href: edit_developers_provider_path(conn["id"]),
            data: { turbo_frame: "drawer-frame" }
          ) do
            render UI::Icon.new(:edit, class: ICON_SM)
            plain "Edit"
          end

          if status != "disabled"
            form(action: deactivate_developers_provider_path(conn["id"]), method: "post",
                 data: { turbo_confirm: "Disable #{label}? Payments will stop routing through it." }) do
              input(type: "hidden", name: "_method",             value: "post")
              input(type: "hidden", name: "authenticity_token",  value: form_authenticity_token)
              button(type: "submit", class: "#{BADGE_SM} #{STATUS_ERROR} cursor-pointer border-0") do
                plain "Disable"
              end
            end
          end
        end
      end
    end

    def status_badge(status)
      css = STATUS_MAP.fetch(status, STATUS_NEUTRAL)
      span(class: "#{BADGE_XS} #{css}") { plain status.capitalize }
    end

    def mode_tag(mode)
      css = mode == "live" ? "#{BADGE_XS} #{STATUS_SUCCESS}" : "#{BADGE_XS} #{STATUS_NEUTRAL}"
      span(class: css) { plain mode.to_s.capitalize }
    end

    def method_tag(method)
      label = { "mobile_money" => "MoMo", "card" => "Card", "bank_transfer" => "Bank" }
                .fetch(method, method.to_s.humanize)
      span(class: "#{BADGE_XS} #{STATUS_NEUTRAL}") { plain label }
    end

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4 mt-2") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "flex w-6 h-6 text-gray-400") { render UI::Icon.new(:layers, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No PSPs connected yet" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-[360px]") do
            plain "Connect Paystack or Flutterwave to enable intelligent multi-PSP routing."
          end
        end
        render UI::Button.new(variant: :primary,
                              href: new_developers_provider_path,
                              data: { turbo_frame: "drawer-frame" }) do
          render UI::Icon.new(:plus, class: ICON_SM)
          plain "Add PSP"
        end
      end
    end
  end
end
