# frozen_string_literal: true

module KybReviews
  class ShowView < ApplicationComponent
    include UI::Theme

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
        render UI::Grid.new(columns: :sidebar) do
          left_column
          right_column
        end
      end
    end

    private

    def left_column
      div(class: "flex flex-col gap-5") do
        applicant_hero
        business_details_card
        ubos_card
        aml_card
        documents_card
      end
    end

    # ── Applicant hero ────────────────────────────────────────────────────────

    def applicant_hero
      div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
        div(class: "flex items-start justify-between mb-6") do
          div(class: "flex items-center gap-4") do
            render UI::Avatar.new(initials, size: :xl)
            div do
              h2(class: "text-[20px] font-bold text-gray-900 tracking-[-0.02em] leading-tight") do
                plain @app.legal_name
              end
              p(class: "#{TYPE_CAPTION} mt-1") do
                plain [ @app.trading_name, country_label ].compact.join(" · ")
              end
              p(class: "#{TYPE_MONO} mt-1.5 text-gray-500") { plain @app.application_code }
            end
          end
          div(class: "flex flex-col items-end gap-2") do
            render UI::StatusBadge.new(status: @app.status)
            p(class: TYPE_CAPTION) { plain "Submitted #{submitted_label}" }
          end
        end
        div(class: "grid grid-cols-4 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
          meta_cell("Industry",     @app.industry&.humanize || "—")
          meta_cell("Team size",    @app.employee_range || "—")
          meta_cell("Submitted by", @app.submitted_by_email || "—")
          meta_cell("Reviewer",     @app.reviewed_by.presence || "Unassigned")
        end
      end
    end

    # ── Business details ──────────────────────────────────────────────────────

    def business_details_card
      render UI::Card.new do |c|
        c.header("Business details", icon: :building)
        c.body(padding: false) do
          detail_row("Legal name",     @app.legal_name)
          detail_row("Trading name",   @app.trading_name.presence || "—")
          detail_row("Country",        country_label)
          detail_row("Industry",       @app.industry&.humanize || "—")
          detail_row("Employee range", @app.employee_range || "—")
          detail_row("Merchant code",  @app.merchant_code.presence || "Pending assignment", mono: true)
          detail_row("Application",    @app.application_code, mono: true)
        end
      end
    end

    # ── Beneficial owners ─────────────────────────────────────────────────────

    def ubos_card
      render UI::Card.new do |c|
        c.header("Beneficial owners (25%+ threshold)", icon: :users)
        c.body(padding: false) do
          empty_state(:users, "No beneficial owners on record",
                      "UBO data will appear here once submitted via the API (P21b).")
        end
      end
    end

    # ── AML / screening ───────────────────────────────────────────────────────

    def aml_card
      render UI::Card.new do |c|
        c.header("AML & sanctions screening", icon: :shield)
        c.body(padding: false) do
          empty_state(:shield, "Screening not yet run",
                      "Automated AML screening will be triggered upon approval (P21b).")
        end
      end
    end

    # ── Documents ─────────────────────────────────────────────────────────────

    def documents_card
      render UI::Card.new do |c|
        c.header("KYB documents", icon: :file)
        c.body(padding: false) do
          empty_state(:file, "No documents uploaded",
                      "Document upload will be available once the KYB documents endpoint ships (P21).")
        end
      end
    end

    # ── Right column ──────────────────────────────────────────────────────────

    def right_column
      div(class: "flex flex-col gap-4") do
        review_actions_card
        review_history_card
      end
    end

    def review_actions_card
      render UI::Card.new do |c|
        c.header("Review decision")
        c.body do
          div(class: "flex flex-col gap-3") do
            if @app.pending?
              approve_form
              hr(class: "border-0 border-t border-gray-100 my-1")
              reject_form
            else
              decided_state
            end
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
                 required: true, class: "#{TEXTAREA_FIELD} mb-2 text-[12.5px]")
        button(type: "submit", class: "#{BTN_DANGER} w-full justify-center") do
          render UI::Icon.new(:alert_circle, class: ICON_SM)
          plain "Reject application"
        end
      end
    end

    def decided_state
      cfg_bg  = @app.approved? ? "rgba(22,163,74,0.08)" : "rgba(220,38,38,0.08)"
      cfg_dot = @app.approved? ? GREEN : RED
      cfg_clr = cfg_dot
      label   = @app.status.capitalize

      div(class: "text-center py-2") do
        div(class: "inline-flex items-center gap-2 px-4 py-2 rounded-xl",
            style: "background:#{cfg_bg}") do
          div(class: "w-2 h-2 rounded-full", style: "background:#{cfg_dot}")
          p(class: "text-[13px] font-semibold", style: "color:#{cfg_clr}") do
            plain "#{label} — no further action"
          end
        end
        if @app.rejected? && @app.rejected_reason.present?
          div(class: "mt-3 px-3 py-[10px] bg-gray-50 rounded-xl text-left") do
            p(class: "#{TYPE_MICRO} mb-1") { plain "Rejection reason" }
            p(class: TYPE_CAPTION) { plain @app.rejected_reason }
          end
        end
      end
    end

    def review_history_card
      div(class: "bg-white border border-gray-100 rounded-2xl px-[18px] py-[18px]") do
        p(class: "#{TYPE_MICRO} mb-3.5") { plain "Review history" }
        div(class: "flex flex-col gap-[10px]") do
          history_row("Submitted", @app.submitted_by_email || "—", submitted_label, "#d97706")
          if @app.reviewed_by.present?
            history_row("Assigned for review", @app.reviewed_by, "—", "#6d28d9")
          end
          if @app.approved_by.present?
            history_row("Approved by", @app.approved_by, "—", GREEN)
          end
        end
      end
    end

    def history_row(action, actor, at, color)
      div(class: "flex gap-3") do
        div(class: "w-2 h-2 rounded-full flex-shrink-0 mt-1", style: "background:#{color}")
        div do
          p(class: TYPE_BODY_MD) { plain action }
          p(class: "#{TYPE_CAPTION} mt-px") { plain "#{actor} · #{at}" }
        end
      end
    end

    # ── Shared helpers ────────────────────────────────────────────────────────

    def detail_row(label, value, mono: false)
      div(class: "flex items-center justify-between px-[22px] py-3 border-b border-gray-100") do
        p(class: TYPE_CAPTION) { plain label }
        p(class: (mono ? TYPE_MONO : TYPE_BODY_MD)) { plain value.to_s }
      end
    end

    def empty_state(icon, title, subtitle)
      div(class: "py-10 px-6 flex flex-col items-center justify-center gap-2 text-center") do
        div(class: "w-10 h-10 rounded-xl bg-gray-100 flex items-center justify-center mb-1") do
          span(class: "text-gray-300 flex w-5 h-5") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        p(class: TYPE_BODY_MD) { plain title }
        p(class: TYPE_CAPTION) { plain subtitle }
      end
    end

    def authenticity_token_field
      input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
    end

    def initials
      parts = @app.legal_name.to_s.split.first(2).map { |w| w[0].upcase }
      s = parts.join.first(2)
      s.empty? ? "??" : s
    end

    def country_label
      COUNTRY_NAMES.fetch(@app.country, @app.country)
    end

    def submitted_label
      @app.last_applied_at&.strftime("%d %b %Y") || "—"
    end
  end
end
