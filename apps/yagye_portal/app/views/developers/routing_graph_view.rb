# frozen_string_literal: true

module Developers
  class RoutingGraphView < ApplicationComponent
    include UI::Theme

    def initialize(configuration:, providers:, mode:)
      @configuration = configuration
      @providers     = providers
      @mode          = mode
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :developers,
        title: @configuration ? @configuration["name"] : "New routing configuration",
        breadcrumbs: [
          { label: "Developers", href: developers_path },
          { label: "Routing Rules", href: developers_routing_rules_path },
          { label: @configuration ? @configuration["name"] : "New" }
        ]
      ) do
        content_for(:head) do
          raw safe('<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/drawflow@0.0.59/dist/drawflow.min.css">')
          raw safe(%(<style>
            #routing-canvas .drawflow { background: #f9fafb; background-image: radial-gradient(#d1d5db 1px, transparent 1px); background-size: 20px 20px; }
            #routing-canvas .drawflow .drawflow-node { background: white; border: 1px solid #e5e7eb; border-radius: 12px; box-shadow: 0 1px 6px rgba(0,0,0,0.06); padding: 0; min-width: 220px; }
            #routing-canvas .drawflow .drawflow-node.selected { border-color: #3D47F5; box-shadow: 0 0 0 3px rgba(61,71,245,0.12); }
            #routing-canvas .drawflow .drawflow-node .inputs, #routing-canvas .drawflow .drawflow-node .outputs { top: 50%; }
            #routing-canvas .drawflow .drawflow-node .input, #routing-canvas .drawflow .drawflow-node .output { width: 12px; height: 12px; border: 2px solid #9ca3af; background: white; border-radius: 50%; }
            #routing-canvas .drawflow .drawflow-node .output:hover, #routing-canvas .drawflow .drawflow-node .input:hover { border-color: #3D47F5; background: #eff0fe; }
            #routing-canvas .drawflow .connection .main-path { stroke: #9ca3af; stroke-width: 2px; }
            #routing-canvas .drawflow .connection.selected .main-path { stroke: #3D47F5; }
          </style>))
        end

        div(class: "flex flex-col", style: "height: calc(100vh - 120px)") do
          editor_toolbar
          div(class: "flex flex-1 min-h-0") do
            node_palette
            canvas_area
            config_panel
          end
        end
      end
    end

    private

    def editor_toolbar
      is_edit    = @configuration && @configuration["id"]
      config_id  = @configuration&.dig("id")
      config_state = @configuration&.dig("state") || "new"

      div(class: "flex items-center justify-between px-5 py-3 bg-white border-b border-gray-100 flex-shrink-0") do
        div(class: "flex items-center gap-3") do
          if is_edit
            input(
              type: "text",
              value: @configuration["name"],
              class: "text-[14px] font-semibold text-gray-900 border-0 outline-none bg-transparent " \
                     "focus:bg-gray-50 focus:rounded-lg px-2 py-1 -ml-2 min-w-[200px]",
              data: { routing_graph_target: "nameInput" }
            )
          else
            input(
              type: "text",
              placeholder: "Configuration name",
              class: "text-[14px] font-semibold text-gray-900 border-0 outline-none bg-transparent " \
                     "focus:bg-gray-50 focus:rounded-lg px-2 py-1 -ml-2 min-w-[200px] placeholder:text-gray-400",
              data: { routing_graph_target: "nameInput" }
            )
          end
          state_chip(config_state)
        end

        div(class: "flex items-center gap-2") do
          render UI::Button.new(variant: :secondary,
                 data: { action: "click->routing-graph#save" }) do
            render UI::Icon.new(:download, class: ICON_SM)
            plain "Save draft"
          end

          if config_state == "draft" && is_edit
            form(action: publish_developers_routing_rule_path(config_id), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              render UI::Button.new(variant: :primary, type: "submit") do
                render UI::Icon.new(:check_circle, class: ICON_SM)
                plain "Publish"
              end
            end
          end
        end
      end
    end

    def state_chip(state)
      css, label = case state
        when "published" then ["badge-green text-[11px] font-semibold px-[9px] py-[3px] rounded-full", "Published"]
        when "archived"  then ["badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full",  "Archived"]
        else                  ["badge-amber text-[11px] font-semibold px-[9px] py-[3px] rounded-full", "Draft"]
      end
      span(class: css) { plain label }
    end

    def node_palette
      div(class: "w-[200px] flex-shrink-0 bg-white border-r border-gray-100 flex flex-col gap-2 p-4 overflow-y-auto") do
        p(class: TYPE_MICRO) { plain "Add nodes" }
        p(class: "#{TYPE_CAPTION} mb-3 mt-1") { plain "Drag onto canvas" }
        palette_node("ProviderNode",  :bank,    "#16a34a", "rgba(22,163,74,0.08)",    "Provider",  "Route to a PSP")
        palette_node("ConditionNode", :filter,  "#d97706", "rgba(217,119,6,0.08)",    "Condition", "Branch on rule")
        palette_node("SplitNode",     :swap,    "#3D47F5", "rgba(61,71,245,0.08)",    "Split",     "Percentage split")
        palette_node("FallbackNode",  :refresh, "#6b7280", "rgba(107,114,128,0.08)", "Fallback",  "On provider fail")
      end
    end

    def palette_node(type, icon, color, bg, label, desc)
      div(
        class: "flex items-start gap-3 p-3 rounded-xl border border-gray-100 cursor-grab " \
               "hover:border-gray-200 hover:shadow-sm transition-all active:cursor-grabbing",
        draggable: "true",
        data: { node_type: type, action: "dragstart->routing-graph#paletteDragStart" }
      ) do
        div(class: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
            style: "background:#{bg}") do
          span(class: "flex w-[14px] h-[14px]", style: "color:#{color}") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div do
          p(class: "text-[12px] font-semibold text-gray-800 leading-tight") { plain label }
          p(class: "text-[10.5px] text-gray-400 leading-tight mt-[2px]") { plain desc }
        end
      end
    end

    def canvas_area
      graph_json    = @configuration&.dig("graph_payload")&.to_json || "null"
      save_url      = @configuration ? developers_routing_rule_path(@configuration["id"]) : developers_routing_rules_path
      save_method   = @configuration ? "patch" : "post"

      div(
        class: "flex-1 min-w-0 relative",
        id: "routing-canvas",
        data: {
          controller: "routing-graph",
          routing_graph_graph_value: graph_json,
          routing_graph_providers_value: @providers.to_json,
          routing_graph_save_url_value: save_url,
          routing_graph_save_method_value: save_method,
          routing_graph_csrf_value: form_authenticity_token
        }
      ) do
        div(class: "absolute inset-0 flex items-center justify-center z-10 pointer-events-none",
            data: { routing_graph_target: "emptyState" }) do
          template_picker
        end
      end
    end

    def template_picker
      div(class: "pointer-events-auto flex flex-col items-center gap-6 max-w-[560px]") do
        div(class: "text-center") do
          p(class: TYPE_DISPLAY) { plain "Start with a template" }
          p(class: "#{TYPE_CAPTION} mt-1") do
            plain "Or drag nodes from the palette on the left to build from scratch."
          end
        end
        div(class: "grid grid-cols-3 gap-3 w-full") do
          template_card("simple_failover",  :refresh, "Simple failover",    "Primary provider with automatic fallback")
          template_card("currency_split",   :swap,    "Currency split",     "Route GHS and non-GHS to different providers")
          template_card("amount_threshold", :filter,  "Amount threshold",   "Route high and low value payments separately")
        end
      end
    end

    def template_card(template_id, icon, title, desc)
      button(
        type: "button",
        class: "text-left p-4 bg-white border border-gray-100 rounded-2xl hover:border-gray-200 " \
               "hover:shadow-md transition-all cursor-pointer group",
        data: {
          action: "click->routing-graph#loadTemplate",
          routing_graph_template_param: template_id
        }
      ) do
        div(class: "w-9 h-9 rounded-xl bg-gray-50 border border-gray-100 flex items-center justify-center " \
                   "mb-3 group-hover:border-gray-200 transition-colors") do
          span(class: "flex w-[15px] h-[15px] text-gray-400") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        p(class: "text-[13px] font-semibold text-gray-900 mb-1") { plain title }
        p(class: "text-[11.5px] text-gray-500 leading-snug") { plain desc }
      end
    end

    def config_panel
      div(
        class: "w-[280px] flex-shrink-0 bg-white border-l border-gray-100 flex flex-col hidden",
        data: { routing_graph_target: "configPanel" }
      ) do
        div(class: "flex items-center justify-between px-5 py-4 border-b border-gray-100") do
          p(class: TYPE_TITLE, data: { routing_graph_target: "panelTitle" }) { plain "Node configuration" }
          button(type: "button", class: BTN_ICON,
                 data: { action: "click->routing-graph#closePanel" }) do
            render UI::Icon.new(:x, class: "w-[13px] h-[13px]")
          end
        end
        div(class: "flex-1 overflow-y-auto p-5",
            data: { routing_graph_target: "panelBody" })
      end
    end
  end
end
