# frozen_string_literal: true

module Developers
  class ProvidersIndexView < ApplicationComponent
    include UI::Theme

    METHOD_LABELS = {
      "mobile_money" => "MoMo",
      "card"         => "Card",
      "bank_transfer" => "Bank"
    }.freeze

    def initialize(connections:, psps:)
      @connections = connections
      @psps        = psps
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :psp_providers,
        title:       "PSP Providers",
        breadcrumbs: [ { label: "PSP Providers" } ]
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
        connections_table
      end
    end

    private

    def stat_band
      total    = @connections.size
      active   = @connections.count { |c| c["status"] == "active" }
      modes    = @connections.map { |c| c["mode"] }.compact.uniq.size
      live_cnt = @connections.count { |c| c["mode"] == "live" && c["status"] == "active" }

      render UI::Grid.new(columns: 4) do
        stat_cell("Connected",   total.to_s,    icon: :layers,       color: BRAND, tint: TINT_BRAND)
        stat_cell("Active",      active.to_s,   icon: :check_circle, color: GREEN, tint: TINT_GREEN)
        stat_cell("Modes",       modes.to_s,    icon: :globe,        color: AMBER, tint: TINT_AMBER)
        stat_cell("Live active", live_cnt.to_s, icon: :bank,         color: GREEN, tint: TINT_GREEN)
      end
    end

    def connections_table
      if @connections.empty?
        empty_state
        return
      end

      div(class: "#{TABLE_CARD} mt-2") do
        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: TABLE_HEADER) do
                th(class: TABLE_TH) { plain "Priority" }
                th(class: TABLE_TH) { plain "Provider" }
                th(class: TABLE_TH) { plain "Mode" }
                th(class: TABLE_TH) { plain "Methods" }
                th(class: TABLE_TH) { plain "Status" }
                th(class: TABLE_TH)
              end
            end
            tbody do
              @connections.sort_by { |c| [ c["priority"].to_i, c["provider_code"].to_s ] }
                          .each { |c| connection_row(c) }
            end
          end
        end
      end
    end

    def connection_row(conn)
      status   = conn["status"] || "active"
      psp_info = @psps.find { |p| p[:code] == conn["provider_code"] } || {}
      label    = psp_info[:label] || conn["provider_name"] || conn["provider_code"].to_s.titleize
      methods  = Array(conn["enabled_methods"])
      priority  = conn["priority"].to_i
      disabled  = status == "disabled"

      tr(class: "#{TABLE_ROW} group #{disabled ? 'opacity-60' : ''}") do
        # Priority — routing order: 1 = highest
        td(class: "#{TABLE_CELL} w-24") do
          div(class: "inline-flex items-center gap-1.5") do
            span(class: "w-5 h-5 rounded-full bg-gray-100 flex items-center justify-center text-[11px] font-bold text-gray-500") do
              plain priority.to_s
            end
            span(class: TYPE_CAPTION) { plain priority == 1 ? "Primary" : "Fallback" }
          end
        end

        # Provider name + code
        td(class: TABLE_CELL) do
          p(class: TYPE_BODY_MD) { plain label }
          p(class: TYPE_CAPTION) { plain conn["provider_code"].to_s }
        end

        # Mode
        td(class: TABLE_CELL) do
          css = conn["mode"] == "live" ? "#{BADGE_XS} #{STATUS_SUCCESS}" : "#{BADGE_XS} #{STATUS_NEUTRAL}"
          span(class: css) { plain (conn["mode"] || "").capitalize }
        end

        # Methods
        td(class: TABLE_CELL) do
          div(class: "flex items-center gap-1 flex-wrap") do
            if methods.any?
              methods.each do |m|
                span(class: "#{BADGE_XS} #{STATUS_NEUTRAL}") do
                  plain METHOD_LABELS.fetch(m, m.to_s.humanize)
                end
              end
            else
              span(class: TYPE_CAPTION) { plain "—" }
            end
          end
        end

        # Status
        td(class: TABLE_CELL) do
          render UI::StatusBadge.new(status)
        end

        # Actions
        td(class: "#{TABLE_CELL} text-right pr-5") do
          div(class: "relative inline-block", data_controller: "dropdown") do
            button(type: "button", class: ROWBTN,
                   data: { action: "click->dropdown#toggle" }) do
              render UI::Icon.new(:dots_vertical, class: ICON_SM)
            end

            div(class: "#{DROPDOWN_MENU} top-full mt-1 right-0 min-w-[160px]",
                data_dropdown_target: "menu") do
              a(href: edit_developers_provider_path(conn["id"]),
                class: DROPDOWN_ITEM,
                data: { turbo_frame: "drawer-frame" }) do
                render UI::Icon.new(:edit, class: ICON_SM)
                plain "Edit"
              end

              unless disabled
                div(class: DROPDOWN_SEP)
                form(action: deactivate_developers_provider_path(conn["id"]), method: "post",
                     data: { turbo_confirm: "Disable #{label}? Payments will stop routing through it." }) do
                  input(type: "hidden", name: "_method",            value: "post")
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                  button(type: "submit", class: DROPDOWN_ITEM_DANGER) { plain "Disable" }
                end
              end
            end
          end
        end
      end
    end

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4 mt-2") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "flex w-6 h-6 text-gray-400") { render UI::Icon.new(:layers, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No PSPs connected yet" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-[360px]") do
            plain "Connect Paystack or Stripe to enable intelligent multi-PSP routing."
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
