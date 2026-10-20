# frozen_string_literal: true

module Notifications
  class RowComponent < ApplicationComponent
    # Urgency left-border colours — fixed semantic alarm colours, not adaptive.
    # These intentionally do NOT use adaptive CSS vars: red and amber must pop
    # equally in light and dark mode to signal urgency.
    URGENCY_BORDER = {
      "critical" => "#dc2626",
      "warning"  => "#d97706",
      "info"     => "transparent"
    }.freeze

    def initialize(notification:)
      @notification = notification
    end

    def view_template
      urgency      = @notification.respond_to?(:urgency) ? @notification.urgency.to_s : "info"
      border_color = URGENCY_BORDER.fetch(urgency, "transparent")

      div(id: "notif-#{@notification.id}",
          style: "border-bottom:1px solid var(--border);") do
        a(href: notification_open_path(@notification),
          style: "display:flex;gap:10px;padding:12px 16px;text-decoration:none;" \
                 "background:#{@notification.read? ? 'var(--card-bg)' : 'var(--notif-unread-bg)'};" \
                 "border-left:3px solid #{border_color};" \
                 "transition:background 120ms;") do
          div(style: "flex-shrink:0;margin-top:2px;") do
            span(style: "display:block;width:7px;height:7px;border-radius:50%;" \
                        "background:#{@notification.read? ? 'var(--subtle-text)' : 'var(--brand)'};" \
                        "margin-top:4px;") { }
          end
          div(style: "flex:1;min-width:0;") do
            p(style: "font-size:12.5px;font-weight:600;color:var(--ink);margin:0 0 2px;" \
                     "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;") do
              plain @notification.title
            end
            p(style: "font-size:11.5px;color:var(--muted-text);margin:0;line-height:1.4;") do
              plain @notification.body.truncate(80)
            end
            p(style: "font-size:10.5px;color:var(--subtle-text);margin:4px 0 0;") do
              plain @notification.created_at.strftime("%-d %b, %H:%M")
            end
          end
        end
      end
    end
  end
end
