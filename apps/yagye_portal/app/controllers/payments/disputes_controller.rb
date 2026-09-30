# frozen_string_literal: true

module Payments
  class DisputesController < ApplicationController
    def index
      authorize :disputes, :index?
      tab   = params[:tab].presence_in(%w[all open won lost]) || "all"
      scope = policy_scope(Dispute)
      pagy, disputes = pagy(
        Payments::DisputesQuery.new(scope).call(
          tab: tab, query: params[:q], reason: params[:reason],
          date_from: params[:from], date_to: params[:to]
        ),
        limit: 25
      )
      render Disputes::IndexView.new(
        tab: tab, disputes: disputes, pagy: pagy,
        query: params[:q], reason: params[:reason],
        date_from: params[:from], date_to: params[:to],
        stats: dispute_stats(scope)
      )
    end

    def filter
      authorize :disputes, :index?
      tab = params[:tab].presence_in(%w[all open won lost]) || "all"
      render Disputes::FilterView.new(
        tab:       tab,
        query:     params[:q],
        reason:    params[:reason],
        date_from: params[:from],
        date_to:   params[:to]
      )
    end

    def show
      authorize :disputes, :show?
      dispute = decode_id(Dispute)
      can_submit = current_user.merchant_user? && dispute.open? && dispute.evidence_text.blank?
      render Disputes::ShowView.new(dispute: dispute, can_submit_evidence: can_submit)
    end

    def submit_evidence
      authorize :disputes, :update?
      dispute = decode_id(Dispute)

      unless current_user.merchant_user? && dispute.open?
        return redirect_to dispute_path(dispute), alert: "Evidence cannot be submitted for this dispute."
      end

      text  = params[:evidence_text].to_s.strip
      files = Array(params[:evidence_files]).reject(&:blank?)

      if text.blank? && files.empty?
        return redirect_to dispute_path(dispute), alert: "Provide evidence text or attach at least one file."
      end

      result = CoreApiClient.new.submit_dispute_evidence(dispute.core_dispute_id)
      if result.success?
        dispute.evidence_files.attach(files) if files.any?
        dispute.update!(evidence_text: text.presence, evidence_submitted_at: Time.current)
        redirect_to dispute_path(dispute), notice: "Evidence submitted successfully."
      else
        redirect_to dispute_path(dispute), alert: "Could not submit evidence. Please try again."
      end
    end

    def resolve
      authorize :disputes, :resolve?
      dispute = decode_id(Dispute)
      outcome = params[:outcome].presence_in(%w[won lost]) || "lost"

      result = CoreApiClient.new.resolve_dispute(dispute.core_dispute_id, outcome)
      if result.success?
        new_status = outcome == "won" ? "won" : "lost"
        dispute.update!(status: new_status, resolved_at: Time.current)
        redirect_to dispute_path(dispute), notice: "Dispute marked as #{outcome}."
      else
        redirect_to dispute_path(dispute), alert: "Could not resolve dispute. Please try again."
      end
    end

    private

    def dispute_stats(scope)
      today = Date.current.to_s
      {
        open:         scope.open.count,
        won:          scope.won.count,
        lost:         scope.lost.count,
        sla_breached: scope.open.where("network_deadline < ?", today).count
      }
    end
  end
end
