# frozen_string_literal: true

module KybReviews
  class ShowView < ApplicationComponent
    include UI::Theme

    STATUS_CFG = {
      "submitted"    => { label: "Submitted",    color: "#d97706", bg: "rgba(217,119,6,0.08)",   dot: "#d97706" },
      "under_review" => { label: "Under review", color: "#6d28d9", bg: "rgba(109,40,217,0.08)",  dot: "#6d28d9" },
      "approved"     => { label: "Approved",     color: "#16a34a", bg: "rgba(22,163,74,0.08)",   dot: "#16a34a" },
      "rejected"     => { label: "Rejected",     color: "#dc2626", bg: "rgba(220,38,38,0.08)",   dot: "#dc2626" }
    }.freeze

    COUNTRY_NAMES = {
      "GH" => "Ghana", "NG" => "Nigeria", "KE" => "Kenya", "ZA" => "South Africa",
      "CI" => "Côte d'Ivoire", "SN" => "Senegal", "CM" => "Cameroon", "TZ" => "Tanzania"
    }.freeze

    def initialize(application:)
      @app = application
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :kyb_reviews,
        title: @app.legal_name,
        breadcrumbs: [
          { label: "KYB Review",   href: kyb_reviews_path },
          { label: @app.legal_name }
        ]
      ) do
        div(style: "display:grid;grid-template-columns:1fr 300px;gap:24px;align-items:start") do
          left_column
          right_column
        end
      end
    end

    private

    # ── Left column ───────────────────────────────────────────────────────────

    def left_column
      div(style: "display:flex;flex-direction:column;gap:20px") do
        applicant_hero
        business_details_card
        ubos_card
        aml_card
        documents_card
      end
    end

    # ── Applicant hero ────────────────────────────────────────────────────────

    def applicant_hero
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:28px 32px") do
        div(style: "display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:24px") do
          # Identity
          div(style: "display:flex;align-items:center;gap:16px") do
            render UI::Avatar.new(initials, size: :xl)
            div do
              h2(style: "font-size:20px;font-weight:700;color:#{INK};letter-spacing:-0.02em;line-height:1.1") do
                plain @app.legal_name
              end
              p(style: "#{TYPE_CAPTION};margin-top:4px") do
                plain [ @app.trading_name, country_label ].compact.join(" · ")
              end
              p(style: "#{TYPE_MONO};margin-top:6px;color:#{MUTED_TEXT}") { @app.application_code }
            end
          end
          # Status pill + submitted date
          div(style: "display:flex;flex-direction:column;align-items:flex-end;gap:8px") do
            status_pill(@app.status)
            p(style: TYPE_CAPTION) { "Submitted #{submitted_label}" }
          end
        end

        # Meta grid
        div(style: "display:grid;grid-template-columns:repeat(4,1fr);gap:1px;" \
                   "background:#{BORDER};border-radius:12px;overflow:hidden") do
          meta_cell("Industry",     @app.industry&.humanize || "—")
          meta_cell("Team size",    @app.employee_range || "—")
          meta_cell("Submitted by", @app.submitted_by_email || "—")
          meta_cell("Reviewer",     @app.reviewed_by.presence || "Unassigned")
        end
      end
    end

    # ── Business details ──────────────────────────────────────────────────────

    def business_details_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        card_header("Business details", :building)
        detail_row("Legal name",    @app.legal_name)
        detail_row("Trading name",  @app.trading_name.presence || "—")
        detail_row("Country",       country_label)
        detail_row("Industry",      @app.industry&.humanize || "—")
        detail_row("Employee range", @app.employee_range || "—")
        detail_row("Merchant code",  @app.merchant_code.presence || "Pending assignment", mono: true)
        detail_row("Application",    @app.application_code, mono: true)
      end
    end

    # ── Beneficial owners ─────────────────────────────────────────────────────

    def ubos_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "display:flex;align-items:center;justify-content:space-between;" \
                   "padding:16px 22px;border-bottom:1px solid #{BORDER}") do
          div(style: "display:flex;align-items:center;gap:10px") do
            icon_spot(:users, MUTED_TEXT)
            p(style: TYPE_TITLE) { "Beneficial owners (25%+ threshold)" }
          end
        end
        empty_state(
          :users,
          "No beneficial owners on record",
          "UBO data will appear here once submitted via the API (P21b)."
        )
      end
    end

    # ── AML / screening ───────────────────────────────────────────────────────

    def aml_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        card_header("AML & sanctions screening", :shield)
        empty_state(
          :shield,
          "Screening not yet run",
          "Automated AML screening will be triggered upon approval (P21b)."
        )
      end
    end

    # ── Documents ─────────────────────────────────────────────────────────────

    def documents_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        card_header("KYB documents", :file)
        empty_state(
          :file,
          "No documents uploaded",
          "Document upload will be available once the KYB documents endpoint ships (P21)."
        )
      end
    end

    # ── Right column ──────────────────────────────────────────────────────────

    def right_column
      div(style: "display:flex;flex-direction:column;gap:16px") do
        review_actions_card
        review_history_card
      end
    end

    def review_actions_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:16px 18px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Review decision" }
        end
        div(style: "padding:16px 18px;display:flex;flex-direction:column;gap:12px") do
          if @app.pending?
            approve_form
            hr(style: "border:none;border-top:1px solid #{BORDER}")
            reject_form
          else
            decided_state
          end
        end
      end
    end

    def approve_form
      form(action: approve_kyb_review_path(@app), method: "post",
           data: { turbo_confirm: "Approve this application?" }) do
        authenticity_token_field
        button(type: "submit",
               class: "bg-[#16a34a] hover:opacity-90 text-white font-semibold rounded-xl " \
                      "text-[13px] px-4 h-9 flex items-center gap-2 w-full justify-center " \
                      "transition-opacity cursor-pointer") do
          render UI::Icon.new(:check_circle, class: ICON_SM)
          plain "Approve application"
        end
      end
    end

    def reject_form
      form(action: reject_kyb_review_path(@app), method: "post") do
        authenticity_token_field
        textarea(name: "reason", rows: 3, placeholder: "Rejection reason (required)…",
                 required: true,
                 style: "width:100%;border:1px solid #{BORDER_MED};border-radius:10px;" \
                        "padding:9px 12px;font-size:12.5px;color:#{INK};resize:vertical;" \
                        "outline:none;margin-bottom:8px;box-sizing:border-box")
        button(type: "submit",
               class: "#{BTN_DANGER} w-full justify-center") do
          render UI::Icon.new(:alert_circle, class: ICON_SM)
          plain "Reject application"
        end
      end
    end

    def decided_state
      cfg = STATUS_CFG.fetch(@app.status, STATUS_CFG["submitted"])
      div(style: "text-align:center;padding:8px 0") do
        div(style: "display:inline-flex;align-items:center;gap:8px;padding:8px 16px;" \
                   "border-radius:12px;background:#{cfg[:bg]}") do
          div(style: "width:8px;height:8px;border-radius:50%;background:#{cfg[:dot]}")
          p(style: "font-size:13px;font-weight:600;color:#{cfg[:color]}") { "#{cfg[:label]} — no further action" }
        end
        if @app.rejected? && @app.rejected_reason.present?
          div(style: "margin-top:12px;padding:10px 12px;background:#{SURFACE};" \
                     "border-radius:10px;text-align:left") do
            p(style: "#{TYPE_MICRO};margin-bottom:4px") { "Rejection reason" }
            p(style: TYPE_CAPTION) { @app.rejected_reason }
          end
        end
      end
    end

    def review_history_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:18px") do
        p(style: "#{TYPE_MICRO};margin-bottom:14px") { "Review history" }
        div(style: "display:flex;flex-direction:column;gap:10px") do
          history_row("Submitted", @app.submitted_by_email || "—", submitted_label, "#d97706")
          if @app.reviewed_by.present?
            history_row("Assigned for review", @app.reviewed_by, "—", "#6d28d9")
          end
          if @app.approved_by.present?
            history_row("Approved by", @app.approved_by, "—", "#16a34a")
          end
        end
      end
    end

    def history_row(action, actor, at, color)
      div(style: "display:flex;gap:12px") do
        div(style: "width:8px;height:8px;border-radius:50%;background:#{color};flex-shrink:0;margin-top:4px")
        div do
          p(style: TYPE_BODY_MD) { action }
          p(style: "#{TYPE_CAPTION};margin-top:1px") { "#{actor} · #{at}" }
        end
      end
    end

    # ── Shared helpers ────────────────────────────────────────────────────────

    def card_header(title, icon)
      div(style: "display:flex;align-items:center;gap:10px;padding:16px 22px;border-bottom:1px solid #{BORDER}") do
        icon_spot(icon, MUTED_TEXT)
        p(style: TYPE_TITLE) { title }
      end
    end

    def icon_spot(icon, color)
      span(style: "display:flex;width:14px;height:14px;color:#{color};flex-shrink:0") do
        render UI::Icon.new(icon, class: "w-full h-full")
      end
    end

    def detail_row(label, value, mono: false)
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:12px 22px;border-bottom:1px solid #{BORDER}") do
        p(style: TYPE_CAPTION) { label }
        p(style: mono ? TYPE_MONO : TYPE_BODY_MD) { value.to_s }
      end
    end

    def meta_cell(label, value)
      div(style: "padding:14px 16px;background:#fff") do
        p(style: "#{TYPE_MICRO};margin-bottom:4px") { label }
        p(style: "font-size:12px;font-weight:500;color:#{INK}") { value.to_s }
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

    def empty_state(icon, title, subtitle)
      div(style: "padding:40px 24px;display:flex;flex-direction:column;align-items:center;" \
                 "justify-content:center;gap:8px;text-align:center") do
        div(style: "width:40px;height:40px;border-radius:12px;background:#{SURFACE};" \
                   "display:flex;align-items:center;justify-content:center;margin-bottom:4px") do
          span(style: "color:#{FAINT_TEXT};display:flex;width:20px;height:20px") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        p(style: TYPE_BODY_MD) { title }
        p(style: TYPE_CAPTION) { subtitle }
      end
    end

    def authenticity_token_field
      input(type: "hidden", name: "authenticity_token",
            value: helpers.form_authenticity_token)
    end

    def initials
      parts = [ @app.legal_name.to_s.split.first(2).map { |w| w[0].upcase } ]
      parts.flatten.join.first(2).then { |s| s.empty? ? "??" : s }
    end

    def country_label
      COUNTRY_NAMES.fetch(@app.country, @app.country)
    end

    def submitted_label
      @app.last_applied_at&.strftime("%d %b %Y") || "—"
    end
  end
end
