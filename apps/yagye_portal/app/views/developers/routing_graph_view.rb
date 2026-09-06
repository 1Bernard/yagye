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
        ],
        padded: false
      ) do
        # Drawflow assets — content_for(:head) is a no-op from Phlex
        link(rel: "stylesheet", href: "https://cdn.jsdelivr.net/npm/drawflow@0.0.59/dist/drawflow.min.css")
        script(src: "https://cdn.jsdelivr.net/npm/drawflow@0.0.59/dist/drawflow.min.js") { }
        canvas_styles

        div(
          class: "relative h-full overflow-hidden",
          data: {
            controller: "routing-graph",
            routing_graph_graph_value: (@configuration&.dig("graph_payload")&.to_json || "{}"),
            routing_graph_providers_value: @providers.to_json,
            routing_graph_save_url_value: (@configuration ? developers_routing_rule_path(@configuration["id"]) : developers_routing_rules_path),
            routing_graph_save_method_value: (@configuration ? "patch" : "post"),
            routing_graph_csrf_value: form_authenticity_token
          }
        ) do
          # Full-area Drawflow canvas — sits behind all floating elements
          div(id: "routing-canvas", class: "absolute inset-0",
              data: { routing_graph_target: "canvas" })

          # Empty state — shown when no nodes exist
          div(class: "absolute inset-0 flex items-center justify-center z-10 pointer-events-none",
              data: { routing_graph_target: "emptyState" }) { empty_state_panel }

          floating_toolbar
          node_picker_panel
          zoom_controls
        end
      end
    end

    private

    # ── Canvas CSS overrides ──────────────────────────────────────────────────

    def canvas_styles
      style do
        raw safe(%(
          #routing-canvas .drawflow {
            background-color: #f8fafc;
            background-image:
              radial-gradient(circle, #d1d5db 1px, transparent 1px);
            background-size: 24px 24px;
          }
          /* Node shell — reset Drawflow's fixed 160×40 px so our card can size it.
             Switch to block layout; ports use position:absolute on the node. */
          #routing-canvas .drawflow .drawflow-node {
            display: block !important;
            width: auto !important;
            height: auto !important;
            background: transparent !important;
            border: none !important;
            box-shadow: none !important;
            padding: 0 !important;
            margin: 0 !important;
            min-width: 0 !important;
            border-radius: 0 !important;
            overflow: visible !important;
            line-height: normal !important;
          }
          #routing-canvas .drawflow .drawflow-node .drawflow_content_node {
            padding: 0;
          }
          /* Port containers — absolute, anchored to top-50% so they self-centre
             regardless of card height. transform nudges them up by half their
             own height (auto height = sum of port dots + gaps). */
          #routing-canvas .drawflow .drawflow-node .inputs,
          #routing-canvas .drawflow .drawflow-node .outputs {
            position: absolute !important;
            top: 50% !important;
            transform: translateY(-50%) !important;
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
            gap: 10px !important;
            width: auto !important;
            float: none !important;
          }
          #routing-canvas .drawflow .drawflow-node .inputs { left: -7px !important; }
          #routing-canvas .drawflow .drawflow-node .outputs { right: -7px !important; }
          /* Individual port dots */
          #routing-canvas .drawflow .drawflow-node .input,
          #routing-canvas .drawflow .drawflow-node .output {
            position: static !important;
            top: auto !important; left: auto !important; right: auto !important;
            margin: 0 !important;
            width: 14px !important; height: 14px !important;
            border: 2px solid rgba(0,0,0,0.15);
            background: white;
            border-radius: 50% !important;
            box-shadow: 0 1px 4px rgba(0,0,0,0.10);
            transition: border-color 0.15s, background 0.15s, transform 0.12s, box-shadow 0.15s;
            cursor: crosshair;
            flex-shrink: 0;
          }
          #routing-canvas .drawflow .drawflow-node .output:hover,
          #routing-canvas .drawflow .drawflow-node .input:hover {
            border-color: #3D47F5 !important;
            background: #eff0fe !important;
            transform: scale(1.35) !important;
            box-shadow: 0 0 0 4px rgba(61,71,245,0.12) !important;
          }
          /* Connection bezier curves */
          #routing-canvas .drawflow .connection .main-path {
            stroke: #a5b4fc;
            stroke-width: 2px;
            stroke-linecap: round;
          }
          #routing-canvas .drawflow .connection.selected .main-path {
            stroke: #3D47F5;
            stroke-width: 2.5px;
          }
          /* Hide Drawflow's native delete badge */
          #routing-canvas .drawflow .drawflow-delete { display: none !important; }
          /* Selected node — elevation glow instead of a hard border color change */
          #routing-canvas .drawflow .drawflow-node.selected .rg-card {
            border-color: rgba(61,71,245,0.18) !important;
            box-shadow: 0 0 0 2.5px rgba(61,71,245,0.16), 0 8px 28px rgba(0,0,0,0.08) !important;
          }
          /* Trash icon: hidden until the node is selected */
          #routing-canvas .drawflow .drawflow-node .rg-del { display: none !important; }
          #routing-canvas .drawflow .drawflow-node.selected .rg-del { display: flex !important; }
        ))
      end
    end

    # ── Floating toolbar (top-center pill) ────────────────────────────────────

    def floating_toolbar
      config_id    = @configuration&.dig("id")
      config_state = @configuration&.dig("state") || "new"

      div(
        class: "absolute top-4 left-1/2 -translate-x-1/2 z-30 flex items-center gap-[6px] " \
               "bg-white border border-gray-200/80 rounded-2xl px-[10px] py-[7px] " \
               "shadow-[0_4px_24px_rgba(0,0,0,0.08)] select-none"
      ) do
        # Back to list
        a(
          href: developers_routing_rules_path,
          class: "flex items-center justify-center w-8 h-8 rounded-xl hover:bg-gray-100 " \
                 "text-gray-400 hover:text-gray-700 transition-colors flex-shrink-0"
        ) do
          span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:chev_left, class: "w-full h-full") }
        end

        div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

        # Editable name input
        input(
          type: "text",
          value: @configuration ? @configuration["name"] : nil,
          placeholder: "Configuration name…",
          class: "text-[13.5px] font-semibold text-gray-900 border-0 outline-none bg-transparent " \
                 "placeholder:text-gray-300 placeholder:font-normal w-[190px] px-1",
          data: { routing_graph_target: "nameInput" }
        )

        state_chip(config_state)
        div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

        # Save draft
        button(
          type: "button",
          class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                 "bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors cursor-pointer border-0",
          data: { action: "click->routing-graph#save" }
        ) do
          span(class: "flex w-[12px] h-[12px]") { render UI::Icon.new(:download, class: "w-full h-full") }
          plain "Save"
        end

        if config_state == "draft" && @configuration
          form(action: publish_developers_routing_rule_path(config_id), method: "post",
               class: "contents") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            button(
              type: "submit",
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                     "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0"
            ) do
              span(class: "flex w-[12px] h-[12px]") { render UI::Icon.new(:check_circle, class: "w-full h-full") }
              plain "Publish"
            end
          end
        end
      end
    end

    def state_chip(state)
      css, label = case state
      when "published" then [ "badge-green text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full", "Published" ]
      when "archived"  then [ "badge-gray  text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full", "Archived" ]
      else                  [ "badge-amber text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full", "Draft" ]
      end
      span(class: css) { plain label }
    end

    # ── Node picker button + dropdown (top-left) ──────────────────────────────

    def node_picker_panel
      div(class: "absolute top-4 left-4 z-30") do
        button(
          type: "button",
          class: "flex items-center gap-[7px] px-[12px] py-[8px] bg-white border border-gray-200/80 " \
                 "rounded-2xl shadow-[0_4px_24px_rgba(0,0,0,0.08)] text-[13px] font-semibold " \
                 "text-gray-700 hover:text-gray-900 hover:shadow-[0_6px_28px_rgba(0,0,0,0.11)] " \
                 "transition-all cursor-pointer border-0",
          style: "border: 1.5px solid rgba(229,231,235,0.9);",
          data: { action: "click->routing-graph#togglePicker" }
        ) do
          span(class: "flex w-[13px] h-[13px] text-gray-500") { render UI::Icon.new(:plus, class: "w-full h-full") }
          plain "Add node"
          span(class: "flex w-[10px] h-[10px] text-gray-400") { render UI::Icon.new(:chev, class: "w-full h-full") }
        end

        # Dropdown — hidden by default, toggled via JS
        div(
          class: "absolute top-full mt-2 left-0 bg-white border border-gray-100 rounded-2xl p-[6px] w-[236px] " \
                 "shadow-[0_8px_32px_rgba(0,0,0,0.10),0_2px_8px_rgba(0,0,0,0.06)]",
          style: "display:none",
          data: { routing_graph_target: "picker" }
        ) do
          picker_section("Routing")
          picker_node("ProviderNode",  :bank,    "#16a34a", "rgba(22,163,74,0.10)",   "Provider",  "Route to a payment provider")
          picker_node("FallbackNode",  :refresh, "#6b7280", "rgba(107,114,128,0.10)", "Fallback",  "Retry with next provider on failure")
          div(class: "h-px bg-gray-100 my-[5px] mx-1")
          picker_section("Logic")
          picker_node("ConditionNode", :filter,  "#d97706", "rgba(217,119,6,0.10)",   "Condition", "Branch on a field value")
          picker_node("SplitNode",     :swap,    "#3D47F5", "rgba(61,71,245,0.10)",   "Split",     "Percentage traffic split")
        end
      end
    end

    def picker_section(text)
      p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-300 px-2 pt-[5px] pb-[3px]") { plain text }
    end

    def picker_node(type, icon, color, bg, label, desc)
      div(
        class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 " \
               "transition-colors cursor-pointer",
        draggable: "true",
        data: {
          node_type: type,
          action: "click->routing-graph#addNodeFromPicker",
          routing_graph_node_type_param: type
        }
      ) do
        div(
          class: "w-8 h-8 rounded-[10px] flex items-center justify-center flex-shrink-0",
          style: "background:#{bg}"
        ) do
          span(class: "flex w-[14px] h-[14px]", style: "color:#{color}") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          p(class: "text-[12.5px] font-semibold text-gray-800 leading-tight") { plain label }
          p(class: "text-[11px] text-gray-400 leading-tight mt-[1px]") { plain desc }
        end
      end
    end

    # ── Zoom controls (bottom-right) ──────────────────────────────────────────

    def zoom_controls
      div(class: "absolute bottom-5 right-5 z-20 flex flex-col gap-[5px]") do
        zoom_btn("+", "click->routing-graph#zoomIn",  "Zoom in")
        zoom_btn("−", "click->routing-graph#zoomOut", "Zoom out")
        button(
          type: "button", title: "Fit to screen",
          class: zoom_btn_class,
          data: { action: "click->routing-graph#fitView" }
        ) do
          span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:grid, class: "w-full h-full") }
        end
      end
    end

    def zoom_btn(label, action, title)
      button(
        type: "button", title: title,
        class: zoom_btn_class,
        data: { action: action }
      ) { plain label }
    end

    def zoom_btn_class
      "w-9 h-9 bg-white border border-gray-200 rounded-xl flex items-center justify-center " \
      "text-gray-500 hover:text-gray-800 hover:border-gray-300 text-[16px] font-light " \
      "transition-all cursor-pointer shadow-[0_2px_8px_rgba(0,0,0,0.06)]"
    end

    # ── Empty state + template picker ─────────────────────────────────────────

    def empty_state_panel
      div(class: "pointer-events-auto flex flex-col items-center gap-6 max-w-[520px] px-4") do
        div(class: "text-center") do
          div(
            class: "w-12 h-12 rounded-2xl bg-white border border-gray-200 flex items-center " \
                   "justify-center mx-auto mb-5 shadow-[0_2px_8px_rgba(0,0,0,0.06)]"
          ) do
            span(class: "flex w-[18px] h-[18px] text-gray-400") do
              render UI::Icon.new(:swap, class: "w-full h-full")
            end
          end
          p(class: "text-[17px] font-bold text-gray-900 tracking-tight mb-1") { plain "Start with a template" }
          p(class: "text-[13px] text-gray-400 leading-snug") do
            plain "Or click "
            span(class: "font-semibold text-gray-600") { plain "+ Add node" }
            plain " to build your routing logic from scratch."
          end
        end

        div(class: "grid grid-cols-3 gap-[10px] w-full") do
          template_card("simple_failover",  :refresh, "#6b7280", "Simple failover",    "Primary PSP with retry on failure")
          template_card("currency_split",   :swap,    "#3D47F5", "Currency split",     "Route by currency — GHS vs. international")
          template_card("amount_threshold", :filter,  "#d97706", "Amount threshold",   "High-value vs. standard routing")
        end
      end
    end

    def template_card(template_id, icon, color, title, desc)
      button(
        type: "button",
        class: "text-left p-[14px] bg-white border border-gray-100 rounded-2xl " \
               "hover:border-gray-200 hover:shadow-lg transition-all cursor-pointer",
        data: {
          action: "click->routing-graph#loadTemplate",
          routing_graph_template_param: template_id
        }
      ) do
        div(
          class: "w-8 h-8 rounded-xl flex items-center justify-center mb-3",
          style: "background:#{color}1A;border:1px solid #{color}22"
        ) do
          span(class: "flex w-[13px] h-[13px]", style: "color:#{color}") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        p(class: "text-[12.5px] font-semibold text-gray-900 mb-[3px] leading-tight") { plain title }
        p(class: "text-[11px] text-gray-400 leading-snug") { plain desc }
      end
    end
  end
end
