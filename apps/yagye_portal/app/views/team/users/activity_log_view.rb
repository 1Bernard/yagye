# frozen_string_literal: true

module Team
  module Users
    class ActivityLogView < ApplicationComponent
      include UI::Theme

      def initialize(events: [])
        @events = events
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :team_users,
          title:      "Team activity log",
          breadcrumbs: [
            { label: "Team", href: team_path },
            { label: "Activity log" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Team activity log",
            subtitle: "Security events across all members of your account."
          )

          div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden mt-6") do
            div(class: "px-6 py-4 border-b border-gray-100 flex items-center justify-between") do
              p(class: TYPE_TITLE) { plain "All events" }
              span(class: "text-[12px] font-medium text-gray-400 tabular-nums") do
                plain "#{@events.size} #{"event".pluralize(@events.size)}"
              end
            end

            if @events.empty?
              div(class: "px-6 py-12 flex flex-col items-center gap-2 text-center") do
                div(class: "w-10 h-10 rounded-xl icon-neutral flex items-center justify-center mb-1") do
                  span(class: "flex w-[16px] h-[16px] text-gray-400") do
                    render UI::Icon.new(:clock, class: "w-full h-full")
                  end
                end
                p(class: "text-[13px] font-semibold text-gray-800") { plain "No activity yet" }
                p(class: TYPE_CAPTION) { plain "Events will appear here as team members use the portal." }
              end
            else
              div do
                @events.each { |event| event_row(event) }
              end
            end
          end
        end
      end

      private

      def event_row(event)
        div(class: "flex items-center gap-4 px-6 py-[13px] border-b border-gray-50 last:border-0") do
          div(class: "w-8 h-8 rounded-xl icon-neutral flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px] text-gray-500") do
              render UI::Icon.new(event.icon, class: "w-full h-full")
            end
          end

          div(class: "flex-1 min-w-0") do
            div(class: "flex items-center gap-2 flex-wrap") do
              p(class: "text-[12.5px] font-semibold text-gray-900 leading-tight") { plain event.label }
              span(class: "text-[11px] font-medium text-gray-400") { plain "·" }
              p(class: "text-[12.5px] font-medium text-gray-600 leading-tight truncate") do
                plain event.user.full_name
              end
            end
            p(class: TYPE_CAPTION) do
              plain event.ip_address.present? ? "from #{event.ip_address}" : "—"
            end
          end

          span(class: "text-[11.5px] font-medium text-gray-400 tabular-nums flex-shrink-0") do
            plain event.created_at.strftime("%d %b, %H:%M")
          end
        end
      end
    end
  end
end
