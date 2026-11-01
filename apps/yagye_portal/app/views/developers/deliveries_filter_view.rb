# frozen_string_literal: true

module Developers
  class DeliveriesFilterView < ApplicationComponent
    include UI::Theme

    STATES = [
      [ "All",        ""          ],
      [ "Delivered",  "delivered" ],
      [ "Failed",     "failed"    ],
      [ "Exhausted",  "exhausted" ],
      [ "Delivering", "delivering"]
    ].freeze

    def initialize(state: nil, event_type: nil, from: nil, to: nil)
      @state      = state
      @event_type = event_type
      @from       = from
      @to         = to
    end

    def view_template
      turbo_frame_tag "drawer-frame", class: "flex flex-col h-full overflow-hidden" do
        render UI::Drawer::Header.new(
          title:        "Filter deliveries",
          subtitle:     "Narrow by state, event type or date.",
          category:     "Webhook Deliveries",
          icon:         :filter,
          palette:      "brand",
          active_count: active_count
        )

        form(action: developers_deliveries_path, method: "get",
             id: "deliveries-filter-form",
             class: "flex-1 overflow-y-auto") do
          render UI::Drawer::Section.new(title: "State", icon: :check_circle, palette: "brand", border: true) do
            render UI::Filter::ChipGroup.new(
              name:        "state",
              options:     STATES,
              selected:    @state,
              status_dots: true
            )
          end

          render UI::Drawer::Section.new(title: "Event type", icon: :layers, palette: "purple", border: true) do
            input(type: "text", name: "event_type", value: @event_type,
                  placeholder: "e.g. payment.succeeded",
                  class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                         "text-gray-700 bg-white outline-none focus:border-indigo-400")
          end

          render UI::Drawer::Section.new(title: "Date range", icon: :calendar, palette: "amber", border: false) do
            render UI::Filter::DateRange.new(from: @from, to: @to)
          end
        end

        render UI::Drawer::Footer.new(
          clear_url:   developers_deliveries_path,
          apply_label: active_count > 0 ? "Apply filters (#{active_count})" : "Apply filters",
          form:        "deliveries-filter-form"
        )
      end
    end

    private

    def active_count
      [
        @state.presence,
        @event_type.presence,
        (@from.presence || @to.presence)
      ].compact.count
    end
  end
end
