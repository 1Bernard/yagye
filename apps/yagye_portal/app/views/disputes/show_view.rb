# frozen_string_literal: true

module Disputes
  class ShowView < ApplicationComponent
    include UI::Theme

    REASON_CFG = {
      "fraud"         => { label: "Fraudulent transaction", color: "#dc2626", tint: "rgba(220,38,38,0.08)" },
      "duplicate"     => { label: "Duplicate charge",       color: "#d97706", tint: "rgba(217,119,6,0.08)" },
      "not_received"  => { label: "Product not received",   color: "#6d28d9", tint: "rgba(109,40,217,0.08)" },
      "unrecognised"  => { label: "Unrecognised charge",    color: "#0d9488", tint: "rgba(13,148,136,0.08)" },
      "other"         => { label: "Other",                  color: "#6b7280", tint: "rgba(107,114,128,0.08)" }
    }.freeze

    def initialize(dispute:, can_submit_evidence: false)
      @dispute             = dispute
      @can_submit_evidence = can_submit_evidence
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :disputes,
        title: @dispute.reference,
        breadcrumbs: [
          { label: "Disputes", href: disputes_path },
          { label: @dispute.reference }
        ]
      ) do
        render UI::Grid.new(columns: :sidebar) do
          left_column
          right_column
        end
      end
    end

    private

    def left_column
      div(class: "flex flex-col gap-5") do
        hero_card
        payment_context_card
        evidence_card
        timeline_card
      end
    end

    def hero_card
      reason = REASON_CFG[@dispute.reason] || REASON_CFG["other"]

      div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
        div(class: "flex items-start justify-between mb-5") do
          div do
            p(class: "#{TYPE_CAPTION} mb-1") { plain "Disputed amount" }
            p(class: "#{TYPE_AMOUNT} text-gray-900") { plain @dispute.formatted_amount }
          end
          div(class: "flex flex-col items-end gap-2") do
            render UI::StatusBadge.new(status: @dispute.status)
            span(class: "inline-flex items-center gap-[6px] px-[10px] py-1 rounded-full text-[11.5px] font-semibold",
                 style: "background:#{reason[:tint]};color:#{reason[:color]}") do
              span(class: "w-[5px] h-[5px] rounded-full flex-shrink-0", style: "background:#{reason[:color]}")
              plain reason[:label]
            end
          end
        end
        div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
          meta_cell("Reference", @dispute.reference, mono: true)
          meta_cell("Opened",   opened_label)
          meta_cell("Customer", @dispute.masked_msisdn)
        end
      end
    end

    def payment_context_card
      render UI::Card.new do |c|
        c.header("Original payment", icon: :credit_card)
        c.body(padding: false) do
          render UI::DetailList.new do |list|
            list.row("Payment reference", @dispute.payment_reference, mono: true)
            list.row("Dispute reference", @dispute.reference, mono: true)
            list.row("Customer MSISDN",   @dispute.masked_msisdn)
            list.row("Network deadline",  @dispute.network_deadline.presence || "—")
            list.row("Resolved",          resolved_label)
          end
        end
      end
    end

    def evidence_card
      render UI::Card.new do |c|
        c.header("Evidence", icon: :file) do
          if @can_submit_evidence && @dispute.open?
            render UI::Button.new(variant: :secondary, style: "cursor:not-allowed;opacity:0.55", disabled: true) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Submit evidence"
            end
          end
        end
        c.body(padding: false) do
          div(class: "py-12 px-6 flex flex-col items-center justify-center gap-[10px] text-center") do
            div(class: "w-11 h-11 rounded-xl bg-gray-50 flex items-center justify-center mb-1") do
              span(class: "text-gray-300 flex w-[22px] h-[22px]") do
                render UI::Icon.new(:file, class: "w-full h-full")
              end
            end
            p(class: TYPE_BODY_MD) { plain "No evidence submitted" }
            p(class: TYPE_CAPTION) { plain "Evidence submission will be available in the next release." }
          end
        end
      end
    end

    def timeline_card
      events = build_timeline
      render UI::Card.new do |c|
        c.header("Activity", icon: :clock)
        c.body do
          div(class: "flex flex-col") do
            events.each_with_index do |(label, at, color), i|
              last = i == events.length - 1
              div(class: "flex gap-[14px]") do
                div(class: "flex flex-col items-center flex-shrink-0") do
                  div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
                  div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless last
                end
                div(class: last ? "" : "pb-[18px]") do
                  p(class: TYPE_BODY_MD) { plain label }
                  p(class: "#{TYPE_CAPTION} mt-px") { plain at }
                end
              end
            end
          end
        end
      end
    end

    def right_column
      div(class: "flex flex-col gap-4") do
        status_card
        sla_card if @dispute.network_deadline.present?
        ops_actions_card if internal_staff_viewer?
      end
    end

    def status_card
      div(class: "bg-white border border-gray-100 rounded-2xl p-5") do
        p(class: "#{TYPE_MICRO} mb-3") { plain "Dispute status" }
        div(class: "flex items-center gap-[10px] px-[14px] py-3 rounded-xl",
            style: "background:#{status_bg}") do
          div(class: "w-2 h-2 rounded-full flex-shrink-0", style: "background:#{status_dot}")
          p(class: "text-[13px] font-semibold", style: "color:#{status_color}") do
            plain @dispute.status.tr("_", " ").split.map(&:capitalize).join(" ")
          end
        end
        if @dispute.opened_at
          div(class: "mt-[14px] flex flex-col gap-[6px]") do
            detail_row_inline("Opened",   opened_label)
            detail_row_inline("Resolved", resolved_label) if @dispute.resolved_at
          end
        end
      end
    end

    def sla_card
      div(class: "bg-white border border-yellow-200 rounded-2xl px-[18px] py-4") do
        div(class: "flex items-center gap-2 mb-2") do
          span(class: "flex w-[14px] h-[14px] text-amber-500 flex-shrink-0") do
            render UI::Icon.new(:clock, class: "w-full h-full")
          end
          p(class: "text-[12.5px] font-bold text-amber-800") { plain "Network deadline" }
        end
        p(class: "#{TYPE_CAPTION} text-amber-600") { plain @dispute.network_deadline }
      end
    end

    def ops_actions_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-[18px] py-4 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Ops actions" }
        end
        div(class: "px-[18px] py-4 flex flex-col gap-2") do
          render UI::Button.new(variant: :secondary,
                 style: "width:100%;justify-content:center;cursor:not-allowed;opacity:0.55",
                 disabled: true) { plain "Mark as won" }
          render UI::Button.new(variant: :danger,
                 style: "width:100%;justify-content:center;cursor:not-allowed;opacity:0.55",
                 disabled: true) { plain "Mark as lost" }
          p(class: "#{TYPE_CAPTION} text-center") { plain "Dispute resolution coming in P12." }
        end
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def detail_row_inline(label, value)
      div(class: "flex items-center justify-between") do
        p(class: TYPE_CAPTION) { plain label }
        p(class: "#{TYPE_CAPTION} text-gray-900 font-medium") { plain value.to_s }
      end
    end

    def status_color
      case @dispute.status
      when "won"          then "#16a34a"
      when "lost"         then "#dc2626"
      when "under_review" then BRAND
      when "closed"       then MUTED_TEXT
      else                     "#d97706"
      end
    end

    def status_dot  = status_color
    def status_bg
      case @dispute.status
      when "won"          then "rgba(22,163,74,0.08)"
      when "lost"         then "rgba(220,38,38,0.08)"
      when "under_review" then "rgba(61,71,245,0.08)"
      when "closed"       then "rgba(107,114,128,0.08)"
      else                     "rgba(217,119,6,0.08)"
      end
    end

    def opened_label
      @dispute.opened_at ? @dispute.opened_at.strftime("%d %b %Y, %H:%M") : "—"
    end

    def resolved_label
      @dispute.resolved_at ? @dispute.resolved_at.strftime("%d %b %Y") : "Pending"
    end

    def build_timeline
      events = []
      events << [ "Dispute opened", opened_label, "#d97706" ]             if @dispute.opened_at
      events << [ "Under review",   "Assigned to compliance",    BRAND ]  if %w[under_review won lost closed].include?(@dispute.status)
      events << [ "Resolved — #{@dispute.status.capitalize}", resolved_label,
                  @dispute.status == "won" ? GREEN : RED ]                if @dispute.resolved_at
      events = [ [ "Dispute opened", opened_label, "#d97706" ] ] if events.empty?
      events
    end

    def internal_staff_viewer?
      Current.user&.internal_staff?
    rescue
      false
    end
  end
end
