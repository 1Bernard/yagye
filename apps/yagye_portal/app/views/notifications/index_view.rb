# frozen_string_literal: true

module Notifications
  class IndexView < ApplicationComponent
    include UI::Theme

    def initialize(notifications:, next_cursor: nil)
      @notifications = notifications
      @next_cursor   = next_cursor
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :notifications,
        title:       "Notifications",
        breadcrumbs: [ { label: "Notifications" } ]
      ) do
        page_header
        notifications_list
        pagination_footer if @next_cursor
      end
    end

    private

    def page_header
      div(class: "flex items-center justify-between mb-6") do
        h1(class: TYPE_DISPLAY) { plain "Notifications" }
        if @notifications.any? { |n| !n.read? }
          a(href: notifications_read_all_path,
            data: { turbo_method: :patch },
            class: "text-[12px] font-medium text-blue-600 hover:text-blue-700 transition-colors") do
            plain "Mark all as read"
          end
        end
      end
    end

    def notifications_list
      if @notifications.empty?
        div(class: "bg-white border border-gray-100 rounded-2xl p-12 text-center") do
          p(class: TYPE_BODY) { plain "You have no notifications." }
        end
      else
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          @notifications.each do |notif|
            render Notifications::RowComponent.new(notification: notif)
          end
        end
      end
    end

    def pagination_footer
      div(class: "mt-4 flex justify-center") do
        a(href: notifications_path(
                  before_created_at: @next_cursor[:created_at],
                  before_id:         @next_cursor[:id]
                ),
          class: "text-[12.5px] text-gray-500 hover:text-gray-700 transition-colors py-2 px-4") do
          plain "Load older notifications"
        end
      end
    end
  end
end
