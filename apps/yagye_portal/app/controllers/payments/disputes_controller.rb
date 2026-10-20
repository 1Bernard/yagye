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
      render Payments::Disputes::IndexView.new(
        tab: tab, disputes: disputes, pagy: pagy,
        query: params[:q], reason: params[:reason],
        date_from: params[:from], date_to: params[:to],
        stats: dispute_stats(scope)
      )
    end

    def filter
      authorize :disputes, :index?
      tab = params[:tab].presence_in(%w[all open won lost]) || "all"
      render Payments::Disputes::FilterView.new(
        tab:       tab,
        query:     params[:q],
        reason:    params[:reason],
        date_from: params[:from],
        date_to:   params[:to]
      )
    end

    def show
      authorize :disputes, :show?
      dispute  = find_owned!(Dispute)
      payment  = dispute.core_payment_id.present? \
        ? policy_scope(Payment).find_by(core_payment_id: dispute.core_payment_id)
        : nil

      deadline_passed = deadline_passed_for(dispute)
      can_draft       = current_user.merchant_user? &&
                        dispute.open? &&
                        dispute.evidence_stage == :none &&
                        !deadline_passed

      can_approve     = policy(dispute).approve_evidence? &&
                        dispute.evidence_stage == :draft &&
                        dispute.evidence_draft_by != current_user.id.to_s &&
                        !deadline_passed

      render Payments::Disputes::ShowView.new(
        dispute:         dispute,
        payment:         payment,
        can_draft:       can_draft,
        can_approve:     can_approve,
        deadline_passed: deadline_passed
      )
    end

    # Maker: save draft, no network call yet.
    def save_evidence_draft
      authorize :disputes, :update?
      dispute = find_owned!(Dispute)

      unless current_user.merchant_user? && dispute.open? && dispute.evidence_stage == :none
        return redirect_to dispute_path(dispute), alert: "Evidence cannot be drafted for this dispute."
      end

      if deadline_passed_for(dispute)
        return redirect_to dispute_path(dispute), alert: "The network deadline has passed."
      end

      text  = params[:evidence_text].to_s.strip
      files = Array(params[:evidence_files]).reject(&:blank?)

      if text.blank? && files.empty?
        return redirect_to dispute_path(dispute), alert: "Provide evidence text or attach at least one file."
      end

      dispute.evidence_draft_files.attach(files) if files.any?
      dispute.update!(
        evidence_draft_text: text.presence,
        evidence_draft_by:   current_user.id.to_s,
        evidence_draft_at:   Time.current
      )

      redirect_to dispute_path(dispute), notice: "Evidence draft saved. A merchant owner must approve before it is submitted."
    end

    # Checker: approve draft and send to network.
    def approve_evidence
      authorize :disputes, :approve_evidence?
      dispute = find_owned!(Dispute)

      unless dispute.evidence_stage == :draft
        return redirect_to dispute_path(dispute), alert: "No draft evidence to approve."
      end

      if dispute.evidence_draft_by == current_user.id.to_s
        return redirect_to dispute_path(dispute), alert: "You cannot approve evidence you prepared."
      end

      if deadline_passed_for(dispute)
        return redirect_to dispute_path(dispute), alert: "The network deadline has passed."
      end

      result = CoreApiClient.new.create_dispute_evidence(dispute.core_dispute_id)
      unless result.success?
        return redirect_to dispute_path(dispute), alert: "Could not submit evidence to the network. Please try again."
      end

      # Promote draft → final
      dispute.evidence_draft_files.each { |f| dispute.evidence_files.attach(f.blob) }
      dispute.update!(
        evidence_text:         dispute.evidence_draft_text,
        evidence_submitted_at: Time.current,
        evidence_approved_by:  current_user.id.to_s,
        evidence_draft_text:   nil,
        evidence_draft_by:     nil,
        evidence_draft_at:     nil
      )
      dispute.evidence_draft_files.purge

      redirect_to dispute_path(dispute), notice: "Evidence submitted to the network."
    end

    # Checker or drafter can discard a draft and start over.
    def discard_evidence_draft
      authorize :disputes, :update?
      dispute = find_owned!(Dispute)

      unless dispute.evidence_stage == :draft
        return redirect_to dispute_path(dispute), alert: "No draft to discard."
      end

      dispute.evidence_draft_files.purge
      dispute.update!(evidence_draft_text: nil, evidence_draft_by: nil, evidence_draft_at: nil)

      redirect_to dispute_path(dispute), notice: "Evidence draft discarded."
    end

    def resolve
      authorize :disputes, :resolve?
      dispute = find_owned!(Dispute)
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

    def resolve_confirm_modal
      authorize :disputes, :resolve?
      @dispute = find_owned!(Dispute)
      outcome = params[:outcome].presence_in(%w[won lost])
      return head(:not_found) unless outcome

      won = outcome == "won"
      render UI::ConfirmModal.new(
        title:         won ? "Mark dispute as won" : "Mark dispute as lost",
        body:          won ? "The payment will return to succeeded and the dispute will be closed." \
                           : "The payment will transition to chargebacked and the dispute will be closed.",
        confirm_path:  resolve_dispute_path(@dispute),
        confirm_label: won ? "Mark as won" : "Mark as lost",
        danger:        !won,
        success:       won,
        hidden_fields: { outcome: outcome }
      )
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

    def deadline_passed_for(dispute)
      return false unless dispute.network_deadline.present?
      deadline = Date.parse(dispute.network_deadline) rescue nil
      deadline&.<(Date.current) || false
    end
  end
end
