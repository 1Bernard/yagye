# frozen_string_literal: true

module Developers
  class RoutingRulesIndexView < ApplicationComponent
    include UI::Theme

    PROVIDER_LABELS = {
      "mtn_momo"     => "MTN MoMo",
      "telecel_cash" => "Telecel Cash",
      "airteltigo"   => "AirtelTigo Money",
      "simulator"    => "Gateway Simulator (test only)"
    }.freeze

    def initialize(configurations:)
      @configurations = configurations
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :routing_rules,
        title: "Routing Rules",
        breadcrumbs: [
          { label: "Operations" },
          { label: "Routing Rules" }
        ]
      ) do
        render UI::PageHeader.new(
          title:    "Routing Rules",
          subtitle: "Define how payments are routed across Yagye's native payment rails."
        ) do
          render UI::Button.new(variant: :primary, href: new_developers_routing_rule_path) do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "New configuration"
          end
        end

        info_banner
        configurations_section
      end
    end

    private

    def info_banner
      div(class: "mb-5 flex items-start gap-3 bg-blue-50 border border-blue-100 rounded-xl px-4 py-3") do
        span(class: "flex w-[15px] h-[15px] text-blue-400 flex-shrink-0 mt-[2px]") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        div do
          p(class: "text-[12.5px] font-semibold text-blue-800") { plain "Platform-scope routing only" }
          p(class: "text-[12px] text-blue-600 mt-[2px] leading-snug") do
            plain "These rules govern live payment routing across Yagye's native rails " \
                  "(MTN MoMo, Telecel Cash, AirtelTigo Money). Only one configuration is active " \
                  "at a time — publishing archives the previous. The Gateway Simulator is available " \
                  "in the editor for building and previewing configurations, but cannot be published " \
                  "— it has no live-mode credentials and is for development use only."
          end
        end
      end
    end

    def configurations_section
      if @configurations.empty?
        empty_state
      else
        published  = @configurations.select { |c| c["state"] == "published" }
        drafts     = @configurations.select { |c| c["state"] == "draft" }
        archived   = @configurations.select { |c| c["state"] == "archived" }

        div(class: "flex flex-col gap-6") do
          active_config_card(published.first) if published.any?
          configurations_table("Drafts", drafts)      if drafts.any?
          configurations_table("Archived", archived)  if archived.any?
        end
      end
    end

    # ── Active configuration — prominent card with compiled rule summary ─────

    def active_config_card(config)
      compiled    = config["compiled_rules"] || {}
      paths       = compiled["paths"] || []
      rule_count  = compiled["rule_count"].to_i
      compiled_at = compiled["compiled_at"]

      div(class: "bg-white border border-green-100 rounded-2xl overflow-hidden") do
        # Header strip
        div(class: "flex items-center justify-between px-6 py-4 border-b border-green-100") do
          div(class: "flex items-center gap-3") do
            div(class: "w-2 h-2 rounded-full bg-green-500",
                style: "box-shadow: 0 0 0 3px rgba(22,163,74,0.15)")
            div do
              p(class: "text-[14px] font-bold text-gray-900 leading-tight") { plain config["name"] }
              p(class: "#{TYPE_MICRO} text-gray-400 mt-[1px]") do
                plain "Active since #{format_published_at(config["published_at"])}"
              end
            end
          end
          div(class: "flex items-center gap-2") do
            span(class: BADGE_SUCCESS) { plain "Published" }
            render UI::Button.new(variant: :secondary,
                   href: edit_developers_routing_rule_path(config["id"])) do
              render UI::Icon.new(:edit, class: ICON_SM)
              plain "Edit"
            end
          end
        end

        # Compiled rules plain-English summary
        div(class: "px-6 py-5") do
          if paths.empty?
            p(class: TYPE_CAPTION) { plain "No rules compiled — edit and republish to activate routing." }
          else
            p(class: "#{TYPE_CAPTION} mb-3 font-semibold text-gray-500 uppercase tracking-wide text-[10.5px]") do
              plain "Active routing paths (#{rule_count} #{rule_count == 1 ? 'rule' : 'rules'})"
            end
            div(class: "flex flex-col gap-[6px]") do
              paths.each_with_index { |path, i| rule_path_row(path, i + 1) }
            end

            if compiled_at
              p(class: "#{TYPE_MICRO} text-gray-400 mt-4") do
                plain "Compiled #{format_compiled_at(compiled_at)}"
              end
            end
          end
        end
      end
    end

    def rule_path_row(path, priority)
      provider  = PROVIDER_LABELS[path["provider"]] || path["provider"] || "Unknown"
      cond_count = path["condition_count"].to_i
      cond_label = cond_count == 0 ? "Default (no conditions — catch-all)" :
                   cond_count == 1 ? "1 condition" : "#{cond_count} conditions"

      div(class: "flex items-center gap-3 py-[9px] px-4 bg-gray-50 rounded-xl") do
        span(class: "w-5 h-5 rounded-full bg-white border border-gray-200 flex items-center justify-center " \
                    "text-[10px] font-bold text-gray-400 flex-shrink-0") { plain priority.to_s }
        div(class: "flex-1 min-w-0") do
          p(class: "text-[13px] font-semibold text-gray-800 leading-tight") { plain "Route to #{provider}" }
          p(class: "#{TYPE_MICRO} text-gray-400 mt-[1px]") { plain cond_label }
        end
        span(class: "text-[11px] font-medium text-gray-400") do
          plain cond_count == 0 ? "fallback" : "priority #{priority}"
        end
      end
    end

    # ── Draft / archived tables ──────────────────────────────────────────────

    def configurations_table(heading, configs)
      div(class: SURFACE_CARD) do
        div(class: "px-5 py-3 border-b border-gray-100") do
          p(class: "text-[12px] font-semibold text-gray-500 uppercase tracking-wide") { plain heading }
        end
        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: TABLE_HEADER) do
                th(class: TABLE_TH) { plain "Name" }
                th(class: TABLE_TH) { plain "State" }
                th(class: TABLE_TH) { plain "Last saved" }
                th(class: TABLE_TH)
              end
            end
            tbody do
              configs.each { |c| configuration_row(c) }
            end
          end
        end
      end
    end

    def configuration_row(config)
      tr(class: TABLE_ROW) do
        td(class: TABLE_CELL) do
          p(class: TYPE_BODY_MD) { plain config["name"] }
          p(class: TYPE_CAPTION) { plain config["public_id"] }
        end
        td(class: TABLE_CELL) { state_badge(config["state"]) }
        td(class: TABLE_CELL) do
          ts = config["updated_at"] || config["inserted_at"]
          plain ts ? Time.parse(ts).strftime("%d %b %Y") : "—"
        end
        td(class: "#{TABLE_CELL} text-right pr-5") do
          render UI::Button.new(variant: :secondary,
                 href: edit_developers_routing_rule_path(config["id"])) do
            render UI::Icon.new(:edit, class: ICON_SM)
            plain "Edit"
          end
        end
      end
    end

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "flex w-6 h-6 text-gray-400") { render UI::Icon.new(:swap, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No routing configurations yet" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-[360px]") do
            plain "Create a configuration to define how payments are routed across native rails."
          end
        end
        render UI::Button.new(variant: :primary, href: new_developers_routing_rule_path) do
          render UI::Icon.new(:plus, class: ICON_SM)
          plain "New configuration"
        end
      end
    end

    def state_badge(state)
      css, label = case state
      when "published" then [ BADGE_SUCCESS, "Published" ]
      when "archived"  then [ BADGE_NEUTRAL, "Archived" ]
      else                  [ BADGE_WARNING, "Draft" ]
      end
      span(class: css) { plain label }
    end

    def format_published_at(ts)
      return "—" unless ts
      Time.parse(ts).strftime("%d %b %Y at %H:%M UTC")
    rescue
      "—"
    end

    def format_compiled_at(ts)
      return "—" unless ts
      Time.parse(ts).strftime("%d %b %Y at %H:%M UTC")
    rescue
      "—"
    end
  end
end
