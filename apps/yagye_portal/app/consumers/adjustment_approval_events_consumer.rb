# frozen_string_literal: true

class AdjustmentApprovalEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      upsert(message.payload)
    rescue StandardError => e
      Rails.logger.error("AdjustmentApprovalEventsConsumer: #{e.message}")
    end
  end

  private

  def upsert(payload)
    break_id = payload["break_id"]
    return unless break_id.present?

    event_id = payload["event_id"].to_s
    existing = PortalAdjustmentApproval.find_by(core_break_id: break_id)
    return if existing&.last_event_id == event_id && event_id.present?

    state = if payload["approved_by"].present? then "approved"
            elsif payload["rejected_reason"].present? then "rejected"
            else "pending"
            end

    attrs = {
      core_break_id:   break_id,
      proposed_by:     payload["proposed_by"],
      proposed_at:     payload["proposed_at"],
      proposed_action: payload["proposed_action"] || {},
      approved_by:     payload["approved_by"],
      approved_at:     payload["approved_at"],
      rejected_reason: payload["rejected_reason"],
      state:           state,
      last_event_id:   event_id
    }.compact

    PortalAdjustmentApproval.upsert(attrs,
      unique_by:   :core_break_id,
      update_only: attrs.keys - [ :core_break_id ])
  end
end
