# frozen_string_literal: true

module Notifications
  class DeliverNotificationJob < ApplicationJob
    queue_as :notifications

    def perform(merchant_code:, event_type:, title:, body:, link: nil, metadata: {},
                mode: "live", urgency: "info", source_event_id: nil)
      Notifications::DeliveryService.deliver(
        merchant_code:   merchant_code,
        event_type:      event_type,
        title:           title,
        body:            body,
        link:            link,
        metadata:        metadata,
        mode:            mode,
        urgency:         urgency,
        source_event_id: source_event_id
      )
    end
  end
end
