# frozen_string_literal: true

class ActivityController < ApplicationController
  def index
    authorize :activity, :index?

    before = params[:before].presence
    domain = params[:tab].presence_in(%w[payment settlement dispute refund account])
    limit  = 50

    core_events  = []
    has_more     = false
    next_cursor  = nil

    # Skip core entirely for the "account" tab — those events live only in AuditLog
    if current_user.merchant_user? && current_user.merchant_code.present? && domain != "account"
      result = CoreApiClient.new.get_merchant_activity(
        merchant_code: current_user.merchant_code,
        before:        before,
        limit:         limit,
        domains:       domain  # nil = all domains; specific string = filter
      )
      if result.success?
        core_events = result.body["data"] || []
        has_more    = result.body.dig("meta", "has_more") || false
        next_cursor = result.body.dig("meta", "next_cursor")
      end
    end

    # Portal audit trail (team/account actions) — always merged unless domain filter excludes it
    audit_events = []
    if domain.nil? || domain == "account"
      audit_scope = current_user.merchant_user? \
        ? AuditLog.where(merchant_code: current_user.merchant_code)
        : AuditLog.all
      audit_scope = audit_scope.where("created_at < ?", before) if before
      audit_events = audit_scope.includes(:user).order(created_at: :desc).limit(limit).map(&:to_activity_event)
    end

    all_events = (core_events + audit_events)
      .sort_by { |e| e["occurred_at"] }
      .reverse
      .first(limit)

    # Pre-resolve portal records for deep-linking
    payment_ids = all_events.select { |e| e["resource_type"] == "payment" }.map { |e| e["resource_id"] }.uniq
    dispute_ids = all_events.select { |e| e["resource_type"] == "dispute" }.map { |e| e["resource_id"] }.uniq

    payment_map = resolve_payments(payment_ids)
    dispute_map = resolve_disputes(dispute_ids)

    render Activity::IndexView.new(
      events:      all_events,
      domain:      domain,
      before:      before,
      has_more:    has_more,
      next_cursor: next_cursor,
      payment_map: payment_map,
      dispute_map: dispute_map
    )
  end

  private

  def resolve_payments(ids)
    return {} if ids.empty?
    scope = current_user.merchant_user? \
      ? Payment.for_merchant(current_user.merchant_code)
      : Payment.all
    scope.where(core_payment_id: ids).index_by(&:core_payment_id)
  rescue StandardError
    {}
  end

  def resolve_disputes(ids)
    return {} if ids.empty?
    scope = current_user.merchant_user? \
      ? Dispute.for_merchant(current_user.merchant_code)
      : Dispute.all
    scope.where(core_dispute_id: ids).index_by(&:core_dispute_id)
  rescue StandardError
    {}
  end
end
