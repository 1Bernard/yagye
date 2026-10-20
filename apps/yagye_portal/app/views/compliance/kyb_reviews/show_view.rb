# frozen_string_literal: true

module Compliance
  module KybReviews
  class ShowView < ApplicationComponent
    include UI::Theme

    COUNTRY_NAMES = {
      "GH" => "Ghana", "NG" => "Nigeria", "KE" => "Kenya", "ZA" => "South Africa",
      "CI" => "Côte d'Ivoire", "SN" => "Senegal", "CM" => "Cameroon", "TZ" => "Tanzania"
    }.freeze

    DOCUMENT_KIND_LABELS = {
      "incorporation"         => "Certificate of Incorporation",
      "id"                    => "Director ID",
      "proof_of_address"      => "Proof of Address",
      "bank_confirmation"     => "Bank Confirmation",
      "form_a"                => "Form A (Beneficial Owners)",
      "business_registration" => "Business Registration Certificate",
      "tax_clearance"         => "Tax Clearance Certificate",
      "bank_statement"        => "Bank Statement"
    }.freeze

    DOC_REVIEW_ACTIONS = {
      "uploaded"     => %w[under_review approved rejected],
      "under_review" => %w[approved rejected],
      "approved"     => [],
      "rejected"     => %w[under_review]
    }.freeze

    DOC_ACTION_LABELS = {
      "under_review" => "Mark under review",
      "approved"     => "Approve document",
      "rejected"     => "Reject document"
    }.freeze

    def initialize(application:, beneficial_owners: [], documents: [], screening: nil, portal_merchant: nil)
      @app               = application
      @beneficial_owners = beneficial_owners
      @documents         = documents
      @screening         = screening
      @portal_merchant   = portal_merchant
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :kyb_reviews,
        title: @app.legal_name,
        breadcrumbs: [
          { label: "KYB Review", href: kyb_reviews_path },
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

    # ── Layout ────────────────────────────────────────────────────────────────

    def left_column
      div(class: "flex flex-col gap-5") do
        applicant_hero
        business_details_card
        ubos_card
        open_hits_card if open_hits.any?
        documents_card
      end
    end

    def right_column
      div(class: "flex flex-col gap-4") do
        review_actions_card
        sandbox_access_card if @app.merchant_code.present?
        live_mode_card if @app.approved? && @app.merchant_code.present?
        review_history_card
      end
    end

    # ── Applicant hero ────────────────────────────────────────────────────────

    def applicant_hero
      div(class: "#{SURFACE_CARD} overflow-hidden") do
        # Header row
        div(class: "flex items-start justify-between px-8 pt-7 pb-6") do
          div(class: "flex items-center gap-4") do
            render UI::Avatar.new(initials, size: :xl)
            div do
              h2(class: "text-[20px] font-bold text-gray-900 tracking-[-0.02em] leading-tight") do
                plain @app.legal_name
              end
              p(class: "#{TYPE_CAPTION} mt-1") do
                plain [ @app.trading_name.presence, country_label ].compact.join(" · ")
              end
              p(class: "#{TYPE_MONO} mt-1.5 text-gray-500") { plain @app.application_code }
            end
          end
          div(class: "flex flex-col items-end gap-2") do
            render UI::StatusBadge.new(status: @app.status)
            p(class: TYPE_CAPTION) { plain "Submitted #{submitted_label}" }
          end
        end

        # Meta strip
        div(class: "grid grid-cols-4 gap-[1px] bg-gray-100") do
          meta_cell("Industry",      @app.industry&.humanize || "—")
          meta_cell("Merchant code", @app.merchant_code.presence || "Pending", mono: true)
          meta_cell("Submitted by",  @app.submitted_by_email || "—")
          meta_cell("Reviewer",      @app.reviewed_by.presence || "Unassigned")
        end

        # Compliance progress strip
        div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 border-t border-gray-100") do
          compliance_pill(
            icon: docs_complete? ? :check_circle : :alert_circle,
            color: docs_complete? ? GREEN : AMBER,
            tint: docs_complete? ? TINT_GREEN : TINT_AMBER,
            label: "#{docs_uploaded}/#{@documents.size} documents",
            sub: docs_complete? ? "All uploaded" : "Upload pending"
          )
          compliance_pill(
            icon: ubos_threshold_clear? ? :check_circle : :alert_circle,
            color: ubos_threshold_clear? ? GREEN : AMBER,
            tint: ubos_threshold_clear? ? TINT_GREEN : TINT_AMBER,
            label: "#{@beneficial_owners.size} beneficial #{"owner".pluralize(@beneficial_owners.size)}",
            sub: ubos_threshold_clear? ? "Threshold met" : "Screening pending"
          )
          compliance_pill(
            icon: screening_clear? ? :check_circle : (open_hits.any? ? :alert_circle : :clock),
            color: screening_clear? ? GREEN : (open_hits.any? ? RED : AMBER),
            tint: screening_clear? ? TINT_GREEN : (open_hits.any? ? TINT_RED : TINT_AMBER),
            label: screening_clear? ? "Screening clear" : "#{open_hits.size} open #{"hit".pluralize(open_hits.size)}",
            sub: screening_label
          )
        end
      end
    end

    def compliance_pill(icon:, color:, tint:, label:, sub:)
      div(class: "flex items-center gap-3 px-5 py-3.5 bg-white") do
        div(class: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
            style: "background:#{tint}") do
          span(class: "flex w-4 h-4", style: "color:#{color}") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div do
          p(class: TYPE_BODY_MD) { plain label }
          p(class: TYPE_CAPTION) { plain sub }
        end
      end
    end

    def meta_cell(label, value, mono: false)
      div(class: "flex flex-col px-5 py-3.5 bg-white") do
        p(class: TYPE_MICRO) { plain label }
        p(class: "#{mono ? TYPE_MONO : TYPE_BODY_MD} mt-0.5 truncate text-gray-700") { plain value }
      end
    end

    # ── Business details ──────────────────────────────────────────────────────

    def business_details_card
      render UI::Card.new do |c|
        c.header("Business details", icon: :building)
        c.body(padding: false) do
          render UI::DetailList.new do |list|
            list.row("Legal name",     @app.legal_name)
            list.row("Trading name",   @app.trading_name.presence || "—")
            list.row("Country",        country_label)
            list.row("Industry",       @app.industry&.humanize || "—")
            list.row("Employee range", @app.employee_range || "—")
            list.row("Merchant code",  @app.merchant_code.presence || "Pending assignment", mono: true)
            list.row("Application",    @app.application_code, mono: true)
          end
        end
      end
    end

    # ── Beneficial owners + screening ─────────────────────────────────────────

    def ubos_card
      render UI::Card.new do |c|
        c.header("Beneficial owners", icon: :users) do
          div(class: "flex items-center gap-2") do
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] " \
                         "font-medium bg-amber-50 text-amber-700") do
              plain "25%+ threshold"
            end
            if @app.merchant_code.present?
              a(href: add_ubo_modal_kyb_review_path(@app),
                class: BTN_SECONDARY + " !py-1 !px-2.5 !text-[11.5px]",
                data: { turbo_frame: "modal-frame" }) do
                render UI::Icon.new(:plus, class: "w-3 h-3")
                plain "Add"
              end
            end
          end
        end
        c.body(padding: @beneficial_owners.empty?) do
          if @beneficial_owners.empty?
            empty_state(:users, "No beneficial owners on record",
                        "Beneficial owners are added by the merchant during onboarding.")
          else
            # Column headers
            div(class: "flex items-center px-5 py-2 border-b border-gray-50 bg-gray-50/60") do
              p(class: "#{TYPE_MICRO} flex-1") { plain "Owner" }
              p(class: "#{TYPE_MICRO} w-20 text-right") { plain "Stake" }
              p(class: "#{TYPE_MICRO} w-28 text-right pr-1") { plain "Screening" }
            end
            div(class: "divide-y divide-gray-50") do
              @beneficial_owners.each { |ubo| ubo_row(ubo) }
            end
          end
        end
      end
    end

    def ubo_row(ubo)
      pct     = ubo["ownership_bps"] ? "#{(ubo["ownership_bps"] / 100.0).round(1)}%" : "—"
      flagged = ubo["ownership_bps"].to_i >= 2500
      name    = ubo["subject_name"].presence ||
                ubo["subject_ref"]&.first(12)&.then { |s| "#{s}…" } || "—"
      inits   = ubo["subject_name"]&.split&.map(&:first)&.join&.upcase&.first(2) || "??"
      subj    = screening_by_subject[ubo["subject_ref"]]

      div(class: "flex items-center gap-3 px-5 py-3.5") do
        render UI::Avatar.new(inits, size: :sm)
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain name }
          p(class: TYPE_CAPTION) do
            parts = [ ubo["role"]&.humanize,
                      ubo["subject_dob"] ? "DOB #{ubo["subject_dob"]}" : nil ]
            plain parts.compact.join(" · ").presence || "—"
          end
        end
        div(class: "w-20 text-right") do
          p(class: "#{TYPE_BODY_MD} tabular-nums") { plain pct }
          if flagged
            p(class: "#{TYPE_CAPTION} text-amber-600 mt-0.5") { plain "≥25%" }
          end
        end
        div(class: "w-28 flex justify-end") do
          screening_badge(subj)
        end
      end
    end

    def screening_badge(subj)
      if subj.nil?
        render UI::Chip.new(label: "Not enrolled", colors: STATUS_NEUTRAL)
      else
        render UI::StatusBadge.new(subj["screening_status"].presence || "pending")
      end
    end

    # ── Open hits (shown only when hits exist) ────────────────────────────────

    def open_hits_card
      render UI::Card.new do |c|
        c.header("Open screening hits", icon: :alert_circle) do
          span(class: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] " \
                       "font-medium bg-red-50 text-red-700") do
            plain "#{open_hits.size} open"
          end
        end
        c.body(padding: false) do
          div(class: "divide-y divide-gray-50") do
            open_hits.each { |hit| hit_row(hit) }
          end
        end
      end
    end

    def hit_row(hit)
      div(class: "flex items-start justify-between px-5 py-3.5") do
        div do
          p(class: TYPE_BODY_MD) { plain hit["matched_name"] || "—" }
          p(class: TYPE_CAPTION) do
            parts = [
              hit["list_type"]&.humanize,
              hit["list_source"],
              hit["match_score"] ? "#{hit["match_score"]}% match" : nil
            ].compact
            plain parts.join(" · ").presence || "—"
          end
        end
        span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] " \
                     "font-medium bg-red-50 text-red-700 shrink-0 ml-3") do
          plain hit["status"]&.humanize || "Open"
        end
      end
    end

    # ── Documents ─────────────────────────────────────────────────────────────

    def documents_card
      render UI::Card.new do |c|
        c.header("KYB documents", icon: :file) do
          if @documents.any?
            span(class: TYPE_CAPTION) do
              plain "#{docs_uploaded} of #{@documents.size} uploaded"
            end
          end
        end
        c.body(padding: @documents.empty?) do
          if @documents.empty?
            empty_state(:file, "No documents uploaded",
                        "The merchant uploads documents through their onboarding portal.")
          else
            # Column headers
            div(class: "flex items-center px-5 py-2 border-b border-gray-50 bg-gray-50/60") do
              p(class: "#{TYPE_MICRO} flex-1") { plain "Document" }
              p(class: "#{TYPE_MICRO} w-28 text-center") { plain "Status" }
              p(class: "#{TYPE_MICRO} w-20 text-center") { plain "Scan" }
              p(class: "#{TYPE_MICRO} w-24 text-right") { plain "Actions" }
            end
            div(class: "divide-y divide-gray-50") do
              @documents.each { |doc| document_row(doc) }
            end
          end
        end
      end
    end

    def document_row(doc)
      label   = DOCUMENT_KIND_LABELS[doc["kind"]] || doc["kind"]&.humanize || "Document"
      scanned = doc["scanned_at"].present?
      status  = doc["status"] || "pending_upload"

      div(class: "flex items-center gap-3 px-5 py-3.5") do
        # File icon
        div(class: "w-8 h-8 rounded-lg bg-teal-50 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-4 h-4 text-teal-600") do
            render UI::Icon.new(:file, class: "w-full h-full")
          end
        end

        # Name + date
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain label }
          p(class: TYPE_CAPTION) do
            plain doc["inserted_at"] ? (fmt_date(Time.parse(doc["inserted_at"])) rescue "—") : "—"
          end
        end

        # Status pill
        div(class: "w-28 flex justify-center") do
          render UI::StatusBadge.new(status)
        end

        # Scan badge
        div(class: "w-20 flex justify-center") do
          if scanned
            span(class: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] " \
                         "font-medium bg-green-50 text-green-700") do
              render UI::Icon.new(:check_circle, class: "w-3 h-3")
              plain "Scanned"
            end
          else
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] " \
                         "font-medium bg-gray-50 text-gray-400") do
              plain "Pending"
            end
          end
        end

        # Actions
        div(class: "w-24 flex items-center justify-end gap-1") do
          # View (opens new tab)
          if status.in?(%w[uploaded under_review approved rejected])
            a(href: kyb_review_document_download_path(@app, doc["id"]),
              target: "_blank",
              rel: "noopener noreferrer",
              class: BTN_SECONDARY + " !py-1 !px-2.5 !text-[11.5px]") do
              render UI::Icon.new(:external_link, class: "w-3 h-3")
              plain "View"
            end
          end

          # Review actions dropdown
          doc_action_dropdown(doc)
        end
      end
    end

    def doc_action_dropdown(doc)
      actions = DOC_REVIEW_ACTIONS.fetch(doc["status"] || "pending_upload", [])
      return if actions.empty?
      return unless @app.merchant_code.present?

      doc_id   = doc["id"]
      doc_stat = doc["status"]

      div(class: "relative inline-block", data: { controller: "dropdown" }) do
        button(type: "button", class: BTN_ICON,
               data: { action: "click->dropdown#toggle" }) do
          render UI::Icon.new(:dots, class: "w-3.5 h-3.5")
        end
        div(class: "#{DROPDOWN_MENU} top-full mt-1 right-0 min-w-[180px]",
            data: { dropdown_target: "menu" }) do
          actions.each do |action|
            action_form_item(doc_id, action, doc_stat)
          end
        end
      end
    end

    def action_form_item(doc_id, action, current_status)
      label  = DOC_ACTION_LABELS[action] || action.humanize
      danger = action == "rejected"
      cls    = danger ? DROPDOWN_ITEM_DANGER : DROPDOWN_ITEM

      if danger
        a(href: reject_document_modal_kyb_review_path(@app, doc_id),
          class: cls,
          data: { turbo_frame: "modal-frame" }) { plain label }
      else
        form(action: kyb_review_document_review_path(@app, doc_id), method: "post") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "status", value: action)
          button(type: "submit", class: cls) { plain label }
        end
      end
    end

    # ── Right column ──────────────────────────────────────────────────────────

    def review_actions_card
      render UI::Card.new do |c|
        c.header("Review decision")
        c.body do
          if @app.pending?
            div(class: "flex flex-col gap-3") do
              # Assignment strip (only when still unassigned)
              if @app.status == "submitted"
                form(action: assign_kyb_review_path(@app), method: "post") do
                  authenticity_token_field
                  button(type: "submit",
                         class: "border border-gray-200 hover:bg-gray-50 text-gray-700 " \
                                "font-medium rounded-xl text-[13px] px-4 h-9 flex items-center " \
                                "gap-2 w-full justify-center transition-colors cursor-pointer") do
                    render UI::Icon.new(:user, class: ICON_SM)
                    plain "Assign to me"
                  end
                end
                div(class: "border-t border-gray-100")
              end

              # Reviewer info strip (when assigned)
              if @app.reviewed_by.present?
                div(class: "flex items-center gap-2 px-1") do
                  div(class: "w-5 h-5 rounded-full bg-violet-50 flex items-center justify-center flex-shrink-0") do
                    span(class: "flex w-3 h-3 text-violet-500") do
                      render UI::Icon.new(:user, class: "w-full h-full")
                    end
                  end
                  p(class: TYPE_CAPTION) do
                    plain "Assigned to "
                    span(class: "font-medium text-gray-700") { plain @app.reviewed_by }
                  end
                end
                div(class: "border-t border-gray-100")
              end

              # Primary actions (compliance_manager only)
              if can?(:approve?, :kyb_reviews)
                a(href: approve_modal_kyb_review_path(@app),
                  class: "#{BTN_SUCCESS} w-full justify-center",
                  data: { turbo_frame: "modal-frame" }) do
                  render UI::Icon.new(:check_circle, class: ICON_SM)
                  plain "Approve application"
                end

                a(href: reject_modal_kyb_review_path(@app),
                  class: "#{BTN_DANGER} w-full justify-center",
                  data: { turbo_frame: "modal-frame" }) do
                  render UI::Icon.new(:alert_circle, class: ICON_SM)
                  plain "Reject application"
                end
              end
            end
          else
            decided_state
          end
        end
      end
    end

    def decided_state
      div(class: "text-center py-2") do
        render UI::StatusBadge.new(@app.approved? ? "approved" : "rejected")
        p(class: "#{TYPE_CAPTION} mt-2") { plain "No further action required." }
        if @app.rejected? && @app.rejected_reason.present?
          div(class: "mt-3 px-3 py-[10px] bg-gray-50 rounded-xl text-left") do
            p(class: "#{TYPE_MICRO} mb-1") { plain "Rejection reason" }
            p(class: TYPE_CAPTION) { plain @app.rejected_reason }
          end
        end
      end
    end

    def sandbox_access_card
      return unless can?(:grant_sandbox?, :kyb_reviews)

      already_sandbox = @portal_merchant&.sandbox_enabled?

      render UI::Card.new do |c|
        c.header("Sandbox access", icon: :layers)
        c.body do
          if already_sandbox
            div(class: "flex items-center gap-2 px-3 py-2 bg-indigo-50 border border-indigo-200 " \
                        "rounded-xl mb-3") do
              span(class: "flex w-4 h-4 text-indigo-500 flex-shrink-0") do
                render UI::Icon.new(:check_circle, class: "w-full h-full")
              end
              p(class: "text-[12.5px] font-semibold text-indigo-800") { plain "PSP sandbox active" }
            end
            p(class: TYPE_CAPTION) do
              plain "Test transactions now route to real provider sandboxes (MTN MoMo, Stripe, etc.) " \
                    "instead of the Yagye simulator."
            end
            if @app.submitted_by_email.present?
              p(class: "#{TYPE_CAPTION} mt-2") do
                plain "Notification sent to "
                span(class: "font-medium text-gray-600") { plain @app.submitted_by_email }
              end
            end
          else
            sandbox_mode_explainer
            a(href: grant_sandbox_modal_kyb_review_path(@app),
              class: "#{BTN_PRIMARY} w-full justify-center mt-3",
              data: { turbo_frame: "modal-frame" }) do
              render UI::Icon.new(:layers, class: ICON_SM)
              plain "Enable sandbox"
            end
            p(class: "#{TYPE_CAPTION} text-center mt-2") do
              plain "Notifies #{@app.submitted_by_email.presence || "the account owner"} by email."
            end
          end
        end
      end
    end

    def sandbox_mode_explainer
      div(class: "flex flex-col gap-2.5 mb-1") do
        # Row 1 — always-on simulation
        div(class: "rounded-xl border border-gray-100 bg-gray-50 px-3 py-2.5") do
          div(class: "flex items-center justify-between mb-1") do
            div(class: "flex items-center gap-1.5") do
              span(class: "w-1.5 h-1.5 rounded-full bg-gray-400 flex-shrink-0")
              p(class: "text-[12px] font-semibold text-gray-600") { plain "Yagye simulation" }
            end
            span(class: "text-[10.5px] font-semibold text-gray-400") { plain "Always on" }
          end
          p(class: "text-[11.5px] text-gray-400 leading-snug") do
            plain "Synthetic responses — instant, no real network calls. Active right now."
          end
        end
        # Row 2 — PSP sandbox (locked until enabled)
        div(class: "rounded-xl border border-amber-200 bg-amber-50 px-3 py-2.5") do
          div(class: "flex items-center justify-between mb-1") do
            div(class: "flex items-center gap-1.5") do
              span(class: "w-1.5 h-1.5 rounded-full bg-amber-400 flex-shrink-0")
              p(class: "text-[12px] font-semibold text-amber-700") { plain "PSP sandbox" }
            end
            span(class: "text-[10.5px] font-semibold text-amber-500") { plain "Locked" }
          end
          p(class: "text-[11.5px] text-amber-600 leading-snug") do
            plain "Real provider test environments: MTN MoMo sandbox, Stripe test mode, etc. Unlocked here."
          end
        end
      end
    end

    def live_mode_card
      return unless can?(:approve?, :kyb_reviews)

      already_live = @portal_merchant&.live_mode_enabled?

      render UI::Card.new do |c|
        c.header("Live mode", icon: :shield)
        c.body do
          if already_live
            div(class: "flex items-center gap-2 px-3 py-2 bg-green-50 border border-green-200 rounded-xl") do
              span(class: "flex w-4 h-4 text-green-600 flex-shrink-0") do
                render UI::Icon.new(:check_circle, class: "w-full h-full")
              end
              p(class: "text-[12.5px] font-semibold text-green-800") { plain "Live mode is active" }
            end
          else
            p(class: "#{TYPE_CAPTION} mb-3") do
              plain "Grant live processing once KYB tier 3+ is confirmed."
            end
            a(href: grant_live_modal_kyb_review_path(@app),
              class: "#{BTN_SUCCESS} w-full justify-center",
              data: { turbo_frame: "modal-frame" }) do
              render UI::Icon.new(:shield, class: ICON_SM)
              plain "Activate live mode"
            end
          end
        end
      end
    end

    def review_history_card
      div(class: "#{SURFACE_CARD} px-[18px] pt-[18px] pb-5") do
        p(class: "#{TYPE_MICRO} mb-4") { plain "Activity timeline" }
        div(class: "flex flex-col") do
          history_events.each_with_index do |ev, i|
            timeline_row(ev, last: i == history_events.size - 1)
          end
        end
      end
    end

    def history_events
      events = []
      events << { label: "Application submitted",
                  actor: @app.submitted_by_email || "Merchant",
                  at:    submitted_label,
                  color: AMBER }
      if @app.reviewed_by.present?
        events << { label: "Assigned for review",
                    actor: @app.reviewed_by,
                    at:    "—",
                    color: PURPLE }
      end
      if @app.approved_by.present?
        events << { label: "Application approved",
                    actor: @app.approved_by,
                    at:    fmt_date(@app.last_applied_at),
                    color: GREEN }
      end
      if @app.rejected?
        snippet = @app.rejected_reason.presence&.truncate(55) || "No reason"
        events << { label: "Rejected — #{snippet}",
                    actor: "Yagye Staff",
                    at:    fmt_date(@app.last_applied_at),
                    color: RED }
      end
      events
    end

    def timeline_row(ev, last: false)
      div(class: "flex gap-3") do
        # Connector column
        div(class: "flex flex-col items-center w-4 flex-shrink-0") do
          div(class: "w-2 h-2 rounded-full mt-1 flex-shrink-0",
              style: "background:#{ev[:color]}")
          unless last
            div(class: "w-px flex-1 mt-1 mb-0", style: "background:#E5E7EB;min-height:20px")
          end
        end
        # Content
        div(class: "#{"mb-4" unless last}") do
          p(class: TYPE_BODY_MD) { plain ev[:label] }
          p(class: "#{TYPE_CAPTION} mt-px") { plain "#{ev[:actor]} · #{ev[:at]}" }
        end
      end
    end

    # ── Shared helpers ────────────────────────────────────────────────────────

    def screening_by_subject
      @screening_by_subject ||= begin
        subjects = @screening&.dig("subjects") || []
        subjects.index_by { |s| s["subject_id"] }
      end
    end

    def open_hits
      @open_hits ||= @screening&.dig("open_hits") || []
    end

    def docs_uploaded
      @documents.count { |d| d["status"].in?(%w[uploaded under_review approved rejected]) }
    end

    def docs_complete?
      @documents.any? && docs_uploaded == @documents.size
    end

    def ubos_threshold_clear?
      return false if @beneficial_owners.empty?
      flagged = @beneficial_owners.select { |u| u["ownership_bps"].to_i >= 2500 }
      flagged.all? do |u|
        subj = screening_by_subject[u["subject_ref"]]
        subj && subj["screening_status"].in?(%w[clean cleared])
      end
    end

    def screening_clear?
      open_hits.empty? &&
        (@screening&.dig("subjects") || []).all? { |s|
          s["screening_status"].in?(%w[clean cleared])
        }
    end

    def screening_label
      return "No subjects enrolled" if (@screening&.dig("subjects") || []).empty?
      total  = (@screening&.dig("subjects") || []).size
      clean  = (@screening&.dig("subjects") || []).count { |s| s["screening_status"].in?(%w[clean cleared]) }
      "#{clean}/#{total} subjects clear"
    end

    def empty_state(icon, title, subtitle)
      div(class: "py-10 px-6 flex flex-col items-center justify-center gap-2 text-center") do
        div(class: "w-10 h-10 rounded-xl bg-gray-50 flex items-center justify-center mb-1") do
          span(class: "flex w-5 h-5 text-gray-300") do
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
      COUNTRY_NAMES.fetch(@app.country.to_s, @app.country.to_s)
    end

    def submitted_label
      fmt_date(@app.last_applied_at)
    end
  end
  end
end
