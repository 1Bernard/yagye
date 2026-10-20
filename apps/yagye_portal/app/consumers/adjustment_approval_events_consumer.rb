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
    evt = Acl::CoreAdjustmentApprovalEvent.new(payload)
    return unless evt.valid?

    existing = PortalAdjustmentApproval.find_by(core_break_id: evt.core_break_id)
    return if existing&.last_event_id == evt.event_id && evt.event_id.present?

    attrs = {
      core_break_id:   evt.core_break_id,
      proposed_by:     evt.proposed_by,
      proposed_at:     evt.proposed_at,
      proposed_action: evt.proposed_action,
      approved_by:     evt.approved_by,
      approved_at:     evt.approved_at,
      rejected_reason: evt.rejected_reason,
      state:           evt.state,
      last_event_id:   evt.event_id
    }.compact

    PortalAdjustmentApproval.upsert(attrs,
      unique_by:   :core_break_id,
      update_only: attrs.keys - [ :core_break_id ])
  end
end
