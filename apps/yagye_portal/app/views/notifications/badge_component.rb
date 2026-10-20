# frozen_string_literal: true

module Notifications
  class BadgeComponent < ApplicationComponent
    def initialize(unread_count:)
      @unread_count = unread_count
    end

    def view_template
      span(id: "notif-bell",
           style: "position:absolute;top:-5px;right:-5px;pointer-events:none;") do
        if @unread_count > 0
          span(style: "display:flex;align-items:center;justify-content:center;" \
                      "min-width:16px;height:16px;padding:0 3px;border-radius:8px;" \
                      "background:#EF4444;font-size:9px;font-weight:700;color:#fff;" \
                      "line-height:1;border:1.5px solid #fff;") do
            plain(@unread_count > 99 ? "99+" : @unread_count.to_s)
          end
        end
      end
    end
  end
end
