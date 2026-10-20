# frozen_string_literal: true

module Acl
  # Translates a raw Core adjustment approval event payload into Portal's model language.
  #
  # Core field      → Portal column     Reason
  # -----------       ---------------   -------
  # break_id        → core_break_id     Portal prefixes Core IDs to make the foreign-key origin explicit
  # proposed_action → proposed_action   JSON blob; no translation needed
  class CoreAdjustmentApprovalEvent
    def initialize(payload)
      @p = payload
    end

    def valid?           = @p["break_id"].present?

    def core_break_id    = @p["break_id"]
    def proposed_by      = @p["proposed_by"]
    def proposed_at      = @p["proposed_at"]
    def proposed_action  = @p["proposed_action"] || {}
    def approved_by      = @p["approved_by"]
    def approved_at      = @p["approved_at"]
    def rejected_reason  = @p["rejected_reason"]
    def event_id         = @p["event_id"].to_s

    def state
      if approved_by.present?    then "approved"
      elsif rejected_reason.present? then "rejected"
      else "pending"
      end
    end
  end
end
