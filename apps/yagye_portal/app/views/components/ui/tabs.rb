# frozen_string_literal: true

module UI
  # Tab bar — renders a row of links or buttons styled as tabs.
  # Tabs with `href:` are real links; tabs without are Stimulus-toggled.
  #
  # Link-based usage (URL-driven):
  #   render UI::Tabs.new do |t|
  #     t.tab "Overview", href: merchant_path(@merchant), active: @section == :overview
  #     t.tab "Payments",  href: payments_merchant_path(@merchant), active: @section == :payments
  #   end
  #
  # JS-toggled usage (same page, different panels):
  #   render UI::Tabs.new(controller: "tabs") do |t|
  #     t.tab "Details", panel: "details", active: true
  #     t.tab "Activity", panel: "activity"
  #   end
  class Tabs < ApplicationComponent
    include UI::Theme

    def initialize(controller: nil, class: nil)
      @controller = controller
      @class      = binding.local_variable_get(:class) || TABS_BAR
      @tabs       = []
    end

    def tab(label, href: nil, active: false, count: nil, panel: nil)
      @tabs << { label: label, href: href, active: active, count: count, panel: panel }
      nil
    end

    def view_template(&block)
      vanish(&block) if block

      div_attrs = { class: @class }
      div_attrs[:data_controller] = @controller if @controller

      div(**div_attrs) do
        @tabs.each { |t| render_tab(t) }
      end
    end

    private

    def render_tab(tab)
      cls = tab[:active] ? TAB_ON : TAB

      if tab[:href]
        a(href: tab[:href], class: cls) do
          plain tab[:label]
          span(class: TAB_COUNT) { tab[:count].to_s } if tab[:count]
        end
      else
        attrs = { class: cls, type: "button" }
        attrs[:data_tabs_target] = "tab" if @controller
        attrs[:data_tabs_panel_param] = tab[:panel] if tab[:panel]
        attrs[:data_action] = "click->#{@controller}#show" if @controller && tab[:panel]

        button(**attrs) do
          plain tab[:label]
          span(class: TAB_COUNT) { tab[:count].to_s } if tab[:count]
        end
      end
    end
  end
end
