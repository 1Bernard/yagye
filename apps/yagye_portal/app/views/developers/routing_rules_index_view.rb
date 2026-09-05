# frozen_string_literal: true

module Developers
  class RoutingRulesIndexView < ApplicationComponent
    include UI::Theme

    def initialize(configurations:)
      @configurations = configurations
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :developers,
        title: "Routing Rules",
        breadcrumbs: [
          { label: "Developers", href: developers_path },
          { label: "Routing Rules" }
        ]
      ) do
        div(class: "flex items-center justify-between mb-5") do
          div do
            p(class: TYPE_BODY) { plain "Manage payment routing configurations for the platform." }
          end
          render UI::Button.new(variant: :primary, href: new_developers_routing_rule_path) do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "New configuration"
          end
        end

        if @configurations.empty?
          empty_state
        else
          configurations_table
        end
      end
    end

    private

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "flex w-6 h-6 text-gray-400") do
            render UI::Icon.new(:swap, class: "w-full h-full")
          end
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No routing configurations yet" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-[360px]") do
            plain "Create a configuration to define how payments are routed to providers."
          end
        end
        render UI::Button.new(variant: :primary, href: new_developers_routing_rule_path) do
          render UI::Icon.new(:plus, class: ICON_SM)
          plain "New configuration"
        end
      end
    end

    def configurations_table
      div(class: SURFACE_CARD) do
        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: TABLE_HEADER) do
                th(class: TABLE_TH) { plain "Name" }
                th(class: TABLE_TH) { plain "Scope" }
                th(class: TABLE_TH) { plain "State" }
                th(class: TABLE_TH) { plain "Published" }
                th(class: TABLE_TH)
              end
            end
            tbody do
              @configurations.each do |config|
                configuration_row(config)
              end
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
        td(class: TABLE_CELL) do
          span(class: "#{TYPE_CAPTION} capitalize") { plain config["scope"] }
        end
        td(class: TABLE_CELL) { state_badge(config["state"]) }
        td(class: TABLE_CELL) do
          if config["published_at"]
            p(class: TYPE_CAPTION) { plain Time.parse(config["published_at"]).strftime("%d %b %Y") }
          else
            span(class: TYPE_CAPTION) { plain "—" }
          end
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

    def state_badge(state)
      css, label = case state
        when "published" then [BADGE_SUCCESS, "Published"]
        when "archived"  then [BADGE_NEUTRAL, "Archived"]
        else                  [BADGE_WARNING, "Draft"]
      end
      span(class: css) { plain label }
    end
  end
end
