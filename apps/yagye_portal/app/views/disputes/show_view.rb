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

    STATUS_CFG = {
      "submitted"    => { label: "Submitted",    color: "#d97706", bg: "rgba(217,119,6,0.08)",   dot: "#d97706" },
      "under_review" => { label: "Under review", color: "#3D47F5", bg: "rgba(61,71,245,0.08)",   dot: "#3D47F5" },
      "won"          => { label: "Won",           color: "#16a34a", bg: "rgba(22,163,74,0.08)",   dot: "#16a34a" },
      "lost"         => { label: "Lost",          color: "#dc2626", bg: "rgba(220,38,38,0.08)",   dot: "#dc2626" },
      "closed"       => { label: "Closed",        color: "#6b7280", bg: "rgba(107,114,128,0.08)", dot: "#9ca3af" }
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
        div(style: "display:grid;grid-template-columns:1fr 320px;gap:24px;align-items:start") do
          left_column
          right_column
        end
      end
    end

    private

    # ── Left column ───────────────────────────────────────────────────────────

    def left_column
      div(style: "display:flex;flex-direction:column;gap:20px") do
        hero_card
        payment_context_card
        evidence_card
        timeline_card
      end
    end

    # ── Hero: amount + reason + status + key meta ─────────────────────────────

    def hero_card
      reason = REASON_CFG[@dispute.reason] || REASON_CFG["other"]

      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:28px 32px") do
        # Top row: amount + status
        div(style: "display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:20px") do
          div do
            p(style: "#{TYPE_CAPTION};margin-bottom:4px") { "Disputed amount" }
            p(style: "#{TYPE_AMOUNT};color:#{INK}") { @dispute.formatted_amount }
          end
          div(style: "display:flex;flex-direction:column;align-items:flex-end;gap:8px") do
            status_pill(@dispute.status)
            # Reason badge
            span(style: "display:inline-flex;align-items:center;gap:6px;padding:4px 10px;" \
                        "border-radius:20px;background:#{reason[:tint]};font-size:11.5px;" \
                        "font-weight:600;color:#{reason[:color]}") do
              span(style: "width:5px;height:5px;border-radius:50%;background:#{reason[:color]};flex-shrink:0")
              plain reason[:label]
            end
          end
        end

        # Meta grid
        div(style: "display:grid;grid-template-columns:repeat(3,1fr);gap:1px;" \
                   "background:#{BORDER};border-radius:12px;overflow:hidden") do
          meta_cell("Reference",    @dispute.reference, mono: true)
          meta_cell("Opened",       opened_label)
          meta_cell("Customer",     @dispute.masked_msisdn)
        end
      end
    end

    # ── Original payment context ───────────────────────────────────────────────

    def payment_context_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        card_header_row("Original payment", :credit_card)
        div(style: "padding:0") do
          detail_row("Payment reference", @dispute.payment_reference, mono: true)
          detail_row("Dispute reference", @dispute.reference, mono: true)
          detail_row("Customer MSISDN",   @dispute.masked_msisdn)
          detail_row("Network deadline",  @dispute.network_deadline.presence || "—")
          detail_row("Resolved",          resolved_label)
        end
      end
    end

    # ── Evidence section ──────────────────────────────────────────────────────

    def evidence_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "display:flex;align-items:center;justify-content:space-between;" \
                   "padding:16px 22px;border-bottom:1px solid #{BORDER}") do
          div(style: "display:flex;align-items:center;gap:10px") do
            span(style: "display:flex;width:14px;height:14px;color:#{MUTED_TEXT}") do
              render UI::Icon.new(:file, class: "w-full h-full")
            end
            p(style: TYPE_TITLE) { "Evidence" }
          end
          if @can_submit_evidence && @dispute.open?
            button(type: "button", class: BTN_SECONDARY,
                   style: "cursor:not-allowed;opacity:0.55", disabled: true) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Submit evidence"
            end
          end
        end
        div(style: "padding:48px 24px;display:flex;flex-direction:column;align-items:center;" \
                   "justify-content:center;gap:10px;text-align:center") do
          div(style: "width:44px;height:44px;border-radius:12px;background:#{SURFACE};" \
                     "display:flex;align-items:center;justify-content:center;margin-bottom:4px") do
            span(style: "color:#{FAINT_TEXT};display:flex;width:22px;height:22px") do
              render UI::Icon.new(:file, class: "w-full h-full")
            end
          end
          p(style: TYPE_BODY_MD) { "No evidence submitted" }
          p(style: TYPE_CAPTION) { "Evidence submission will be available in the next release." }
        end
      end
    end

    # ── Activity timeline ─────────────────────────────────────────────────────

    def timeline_card
      events = build_timeline

      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        card_header_row("Activity", :clock)
        div(style: "padding:20px 24px") do
          events.each_with_index do |(label, at, color), i|
            last = i == events.length - 1
            div(style: "display:flex;gap:14px") do
              div(style: "display:flex;flex-direction:column;align-items:center;flex-shrink:0") do
                div(style: "width:10px;height:10px;border-radius:50%;background:#{color};" \
                           "flex-shrink:0;margin-top:3px")
                unless last
                  div(style: "width:1px;flex:1;background:#{BORDER};margin:4px 0")
                end
              end
              div(style: "padding-bottom:#{last ? '0' : '18px'}") do
                p(style: TYPE_BODY_MD) { label }
                p(style: "#{TYPE_CAPTION};margin-top:1px") { at }
              end
            end
          end
        end
      end
    end

    # ── Right column ──────────────────────────────────────────────────────────

    def right_column
      div(style: "display:flex;flex-direction:column;gap:16px") do
        status_card
        sla_card if @dispute.network_deadline.present?
        ops_actions_card if internal_staff_viewer?
      end
    end

    def status_card
      cfg = STATUS_CFG.fetch(@dispute.status, STATUS_CFG["submitted"])

      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:20px") do
        p(style: "#{TYPE_MICRO};margin-bottom:12px") { "Dispute status" }
        div(style: "display:flex;align-items:center;gap:10px;padding:12px 14px;" \
                   "background:#{cfg[:bg]};border-radius:12px") do
          div(style: "width:8px;height:8px;border-radius:50%;background:#{cfg[:dot]};flex-shrink:0")
          p(style: "font-size:13px;font-weight:600;color:#{cfg[:color]}") { cfg[:label] }
        end
        if @dispute.opened_at
          div(style: "margin-top:14px;display:flex;flex-direction:column;gap:6px") do
            detail_row_inline("Opened", opened_label)
            detail_row_inline("Resolved", resolved_label) if @dispute.resolved_at
          end
        end
      end
    end

    def sla_card
      div(style: "background:#fff;border:1px solid #fde68a;border-radius:16px;padding:16px 18px") do
        div(style: "display:flex;align-items:center;gap:8px;margin-bottom:8px") do
          span(style: "display:flex;width:14px;height:14px;color:#d97706;flex-shrink:0") do
            render UI::Icon.new(:clock, class: "w-full h-full")
          end
          p(style: "font-size:12.5px;font-weight:700;color:#92400e") { "Network deadline" }
        end
        p(style: "#{TYPE_CAPTION};color:#b45309") { @dispute.network_deadline }
      end
    end

    def ops_actions_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:16px 18px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Ops actions" }
        end
        div(style: "padding:16px 18px;display:flex;flex-direction:column;gap:8px") do
          button(type: "button", class: BTN_SECONDARY,
                 style: "width:100%;justify-content:center;cursor:not-allowed;opacity:0.55",
                 disabled: true) do
            plain "Mark as won"
          end
          button(type: "button", class: BTN_DANGER,
                 style: "width:100%;justify-content:center;cursor:not-allowed;opacity:0.55",
                 disabled: true) do
            plain "Mark as lost"
          end
          p(style: "#{TYPE_CAPTION};text-align:center") { "Dispute resolution coming in P12." }
        end
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def card_header_row(title, icon)
      div(style: "display:flex;align-items:center;gap:10px;padding:16px 22px;border-bottom:1px solid #{BORDER}") do
        span(style: "display:flex;width:14px;height:14px;color:#{MUTED_TEXT}") do
          render UI::Icon.new(icon, class: "w-full h-full")
        end
        p(style: TYPE_TITLE) { title }
      end
    end

    def detail_row(label, value, mono: false)
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:12px 22px;border-bottom:1px solid #{BORDER}") do
        p(style: TYPE_CAPTION) { label }
        p(style: mono ? TYPE_MONO : TYPE_BODY_MD) { value.to_s }
      end
    end

    def detail_row_inline(label, value)
      div(style: "display:flex;align-items:center;justify-content:space-between") do
        p(style: TYPE_CAPTION) { label }
        p(style: "#{TYPE_CAPTION};color:#{INK};font-weight:500") { value.to_s }
      end
    end

    def meta_cell(label, value, mono: false)
      div(style: "padding:14px 16px;background:#fff") do
        p(style: "#{TYPE_MICRO};margin-bottom:4px") { label }
        p(style: mono ? TYPE_MONO : TYPE_BODY_MD) { value.to_s }
      end
    end

    def status_pill(status)
      cfg = STATUS_CFG.fetch(status, STATUS_CFG["submitted"])
      span(style: "display:inline-flex;align-items:center;gap:6px;padding:4px 12px;" \
                  "border-radius:20px;background:#{cfg[:bg]}") do
        span(style: "width:6px;height:6px;border-radius:50%;background:#{cfg[:dot]};flex-shrink:0")
        span(style: "font-size:12px;font-weight:600;color:#{cfg[:color]}") { cfg[:label] }
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
      events << [ "Under review",   "Assigned to compliance",    "#3D47F5" ] if %w[under_review won lost closed].include?(@dispute.status)
      events << [ "Resolved — #{@dispute.status.capitalize}", resolved_label, @dispute.status == "won" ? "#16a34a" : "#dc2626" ] if @dispute.resolved_at
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
