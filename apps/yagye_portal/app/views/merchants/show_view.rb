# frozen_string_literal: true

module Merchants
  class ShowView < ApplicationComponent
    include UI::Theme

    DOCUMENT_KIND_LABELS = {
      "incorporation"    => "Certificate of Incorporation",
      "id"               => "Director ID",
      "proof_of_address" => "Proof of Address",
      "bank_confirmation" => "Bank Confirmation"
    }.freeze

    SCREENING_STATUS_LABELS = {
      "pending"                 => "Pending",
      "clean"                   => "Clear",
      "cleared"                 => "Cleared",
      "potential_match"         => "Potential match",
      "confirmed_pep"           => "Confirmed PEP",
      "confirmed_match_blocked" => "Blocked",
      "suspended"               => "Suspended"
    }.freeze

    def initialize(application:, beneficial_owners: [], documents: [], screening: nil, reserve_policy: nil)
      @app               = application
      @beneficial_owners = beneficial_owners
      @documents         = documents
      @screening         = screening
      @reserve_policy    = reserve_policy
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :merchants,
        title:      @app.legal_name || @app.merchant_code,
        breadcrumbs: [
          { label: "Merchants", url: merchants_path },
          { label: @app.legal_name || @app.merchant_code }
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
        business_card
        kyb_card
        beneficial_owners_card
        documents_card
      end
    end

    def right_column
      div(class: "flex flex-col gap-5") do
        actions_card
        reserve_policy_card if @app.merchant_code.present? && can?(:manage?, :reserve_policies)
        status_card
      end
    end

    # ── Business hero card ────────────────────────────────────────────────────

    def business_card
      div(class: "#{SURFACE_CARD} overflow-hidden") do
        div(class: "flex items-start justify-between px-8 pt-7 pb-6") do
          div(class: "flex items-center gap-4") do
            render UI::Avatar.new(initials, size: :xl)
            div do
              p(class: "text-[20px] font-bold text-gray-900 tracking-[-0.02em] leading-tight") do
                plain @app.legal_name || "—"
              end
              p(class: "#{TYPE_CAPTION} mt-1") do
                plain [ @app.trading_name.presence, country_label ].compact.join(" · ")
              end
              p(class: "#{TYPE_MONO} mt-1.5 text-gray-500") { plain @app.merchant_code }
            end
          end
          div(class: "flex flex-col items-end gap-2") do
            render UI::StatusBadge.new(status: @app.status)
            p(class: TYPE_CAPTION) { plain "Submitted #{fmt_date(@app.last_applied_at)}" }
          end
        end

        # Detail strip
        div(class: "grid grid-cols-4 gap-[1px] bg-gray-100 border-t border-gray-100") do
          meta_cell("Industry",      @app.industry&.humanize || "—")
          meta_cell("Merchant code", @app.merchant_code || "—", mono: true)
          meta_cell("Submitted by",  @app.submitted_by_email || "—")
          meta_cell("Applied",       fmt_date(@app.last_applied_at))
        end

        # Compliance progress strip
        div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 border-t border-gray-100") do
          compliance_pill(
            icon:  docs_complete? ? :check_circle : :alert_circle,
            color: docs_complete? ? GREEN : AMBER,
            tint:  docs_complete? ? TINT_GREEN : TINT_AMBER,
            label: "#{docs_uploaded}/#{@documents.size} documents",
            sub:   docs_complete? ? "All uploaded" : "Pending uploads"
          )
          compliance_pill(
            icon:  ubos_threshold_clear? ? :check_circle : :alert_circle,
            color: ubos_threshold_clear? ? GREEN : AMBER,
            tint:  ubos_threshold_clear? ? TINT_GREEN : TINT_AMBER,
            label: "#{@beneficial_owners.size} beneficial #{"owner".pluralize(@beneficial_owners.size)}",
            sub:   ubos_threshold_clear? ? "Threshold met" : "Screening pending"
          )
          compliance_pill(
            icon:  screening_clear? ? :check_circle : (open_hits.any? ? :alert_circle : :clock),
            color: screening_clear? ? GREEN : (open_hits.any? ? RED : AMBER),
            tint:  screening_clear? ? TINT_GREEN : (open_hits.any? ? TINT_RED : TINT_AMBER),
            label: screening_clear? ? "Screening clear" : "#{open_hits.size} open #{"hit".pluralize(open_hits.size)}",
            sub:   screening_summary_label
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

    # ── KYB details card ──────────────────────────────────────────────────────

    def kyb_card
      render UI::Card.new do |c|
        c.header("Business details", icon: :building)
        c.body(padding: false) do
          render UI::DetailList.new do |list|
            list.row("Legal name",     @app.legal_name)
            list.row("Trading name",   @app.trading_name.presence || "—")
            list.row("Country",        country_label)
            list.row("Industry",       @app.industry&.humanize || "—")
            list.row("Employee range", @app.employee_range || "—")
            list.row("Merchant code",  @app.merchant_code.presence || "—", mono: true)
            list.row("Application",    @app.application_code, mono: true)
            list.row("Rejected reason", @app.rejected_reason.presence || "—") if @app.rejected?
          end
        end
      end
    end

    # ── Beneficial owners card ────────────────────────────────────────────────

    def beneficial_owners_card
      render UI::Card.new do |c|
        c.header("Beneficial owners") do
          span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] " \
                       "font-medium bg-amber-50 text-amber-700") do
            plain "25%+ threshold"
          end
        end
        c.body(padding: @beneficial_owners.empty?) do
          if @beneficial_owners.empty?
            empty_state(:users, "No beneficial owners on record",
                        "Beneficial owners are added by the merchant during onboarding.")
          else
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
                ubo["subject_ref"]&.first(14)&.then { |s| "#{s}…" } || "—"
      inits   = ubo["subject_name"]&.split&.map(&:first)&.join&.upcase&.first(2) ||
                ubo["subject_ref"]&.first(2)&.upcase || "??"
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
          p(class: "#{TYPE_CAPTION} text-amber-600 mt-0.5") { plain "≥25%" } if flagged
        end
        div(class: "w-28 flex justify-end") do
          ubo_screening_badge(subj)
        end
      end
    end

    def ubo_screening_badge(subj)
      if subj.nil?
        render UI::Chip.new(label: "Not enrolled", colors: STATUS_NEUTRAL)
      else
        render UI::StatusBadge.new(subj["screening_status"].presence || "pending")
      end
    end

    # ── KYB documents card ────────────────────────────────────────────────────

    def documents_card
      render UI::Card.new do |c|
        c.header("KYB documents") do
          span(class: TYPE_CAPTION) { plain "#{docs_uploaded} of #{@documents.size} uploaded" } if @documents.any?
        end
        c.body(padding: @documents.empty?) do
          if @documents.empty?
            empty_state(:file, "No documents uploaded",
                        "The merchant uploads documents through their onboarding portal.")
          else
            div(class: "flex items-center px-5 py-2 border-b border-gray-50 bg-gray-50/60") do
              p(class: "#{TYPE_MICRO} flex-1") { plain "Document" }
              p(class: "#{TYPE_MICRO} w-28 text-center") { plain "Status" }
              p(class: "#{TYPE_MICRO} w-20 text-right") { plain "Scan" }
            end
            div(class: "divide-y divide-gray-50") do
              @documents.each { |doc| document_row(doc) }
            end
          end
        end
      end
    end

    def document_row(doc)
      label    = DOCUMENT_KIND_LABELS[doc["kind"]] || doc["kind"]&.humanize || "Document"
      scanned  = doc["scanned_at"].present?
      status   = doc["status"] || "pending_upload"
      date_str = begin
        fmt_date(Time.parse(doc["inserted_at"])) if doc["inserted_at"]
      rescue
        nil
      end

      div(class: "flex items-center gap-3 px-5 py-3.5") do
        div(class: "w-8 h-8 rounded-lg bg-teal-50 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-4 h-4 text-teal-600") do
            render UI::Icon.new(:file, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain label }
          p(class: TYPE_CAPTION) { plain date_str ? "Uploaded #{date_str}" : "—" }
        end
        div(class: "w-28 flex justify-center") do
          render UI::StatusBadge.new(status)
        end
        div(class: "w-20 flex justify-end") do
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
      end
    end

    # ── Status card ───────────────────────────────────────────────────────────

    def status_card
      render UI::Card.new do |c|
        c.header("Application status")
        c.body do
          div(class: "flex items-center gap-[10px] mb-3") do
            render UI::StatusBadge.new(status: @app.status)
            p(class: TYPE_CAPTION) { plain @app.status_label }
          end
          p(class: TYPE_CAPTION) do
            plain "Last updated #{fmt_datetime(@app.last_applied_at)}"
          end
          if @app.reviewed_by.present? || @app.approved_by.present?
            div(class: "divide-y divide-gray-50 mt-3 pt-3 border-t border-gray-100") do
              reserve_detail_row("Reviewed by", @app.reviewed_by) if @app.reviewed_by.present?
              reserve_detail_row("Approved by", @app.approved_by) if @app.approved_by.present?
            end
          end
        end
      end
    end

    # ── AML Screening card ────────────────────────────────────────────────────

    def screening_card
      subjects  = @screening["subjects"]  || []
      clear     = open_hits.empty?

      render UI::Card.new do |c|
        c.header("AML screening")
        c.body(padding: subjects.empty?) do
          if subjects.empty?
            empty_state(:shield, "No subjects enrolled",
                        "Screening subjects are enrolled when beneficial owners are added.")
          else
            # Summary banner
            div(class: "flex items-center gap-2 mb-3") do
              if clear
                span(class: "flex w-4 h-4 text-green-500 flex-shrink-0") do
                  render UI::Icon.new(:check_circle, class: "w-full h-full")
                end
                p(class: "#{TYPE_BODY_MD} text-green-700") { plain "No open hits" }
              else
                span(class: "flex w-4 h-4 text-red-500 flex-shrink-0") do
                  render UI::Icon.new(:alert_circle, class: "w-full h-full")
                end
                p(class: "#{TYPE_BODY_MD} text-red-700") do
                  plain "#{open_hits.size} open #{"hit".pluralize(open_hits.size)}"
                end
              end
            end

            # Per-subject rows with resolved identity
            div(class: "divide-y divide-gray-50") do
              subjects.each do |subj|
                subject_row(subj)
              end
            end
          end
        end
      end
    end

    def subject_row(subj)
      ubo      = @beneficial_owners.find { |u| u["subject_ref"] == subj["subject_id"] }
      name     = ubo&.dig("subject_name").presence ||
                 subj["subject_id"]&.first(14)&.then { "#{_1}…" } || "—"
      role     = ubo&.dig("role")&.humanize || subj["subject_type"]&.humanize || "Subject"
      status   = subj["screening_status"].presence || "pending"
      label    = SCREENING_STATUS_LABELS.fetch(status, status.humanize)

      div(class: "flex items-center gap-3 py-3") do
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain name }
          p(class: TYPE_CAPTION) { plain role }
        end
        render UI::StatusBadge.new(status)
      end
    end

    # ── Reserve policy card (ops only) ───────────────────────────────────────

    def reserve_policy_card
      pol_status = @reserve_policy && (@reserve_policy["status"] ||
                   (@reserve_policy["approved_by"].present? ? "active" : "pending_approval"))
      # Policy is locked once created — "Set policy" only available when none exists or deactivated.
      can_create = @reserve_policy.nil? || pol_status == "inactive"

      render UI::Card.new do |c|
        c.header("Reserve policy", icon: :lock) do
          if can_create
            a(href: new_modal_merchant_reserve_policy_path(@app),
              class: "#{BTN_SECONDARY} !py-1 !px-2.5 !text-[11.5px] inline-flex items-center gap-1",
              data: { turbo_frame: "modal-frame" }) do
              render UI::Icon.new(:plus, class: "w-3 h-3")
              plain "Set policy"
            end
          end
        end
        c.body do
          if @reserve_policy.nil?
            p(class: TYPE_CAPTION) { plain "No reserve policy configured." }
          else
            reserve_policy_body(@reserve_policy)
          end
        end
      end
    end

    def reserve_policy_body(pol)
      status = pol["status"] || (pol["approved_by"].present? ? "active" : "pending_approval")

      # Status banner
      case status
      when "active"
        status_banner(:check_circle, "bg-green-50 border-green-200", "text-green-600",
                      "text-green-800", "Active — funds withheld on settlement")
      when "awaiting_merchant_ack"
        auto_date = begin Time.parse(pol["auto_activates_at"].to_s).strftime("%-d %b %Y") rescue "pending" end
        div(class: "flex items-start gap-2 px-3 py-2.5 bg-blue-50 border border-blue-200 rounded-xl mb-3") do
          span(class: "flex w-4 h-4 text-blue-500 flex-shrink-0 mt-0.5") { render UI::Icon.new(:clock, class: "w-full h-full") }
          div do
            p(class: "text-[12px] font-semibold text-blue-800") { plain "Awaiting merchant acknowledgment" }
            p(class: "text-[11px] text-blue-600 mt-0.5") { plain "Auto-activates #{auto_date} if unacknowledged." }
          end
        end
      when "inactive"
        status_banner(:minus, "bg-gray-50 border-gray-200", "text-gray-400",
                      "text-gray-500", "Inactive — not withholding funds")
      else
        status_banner(:clock, "bg-amber-50 border-amber-200", "text-amber-500",
                      "text-amber-800", "Pending ops approval — not yet withholding")
      end

      # Detail rows
      div(class: "divide-y divide-gray-50 mb-3") do
        reserve_detail_row("Type",       policy_kind_label(pol["kind"]))
        if pol["kind"] == "rolling"
          reserve_detail_row("Rate",     "#{(pol["percentage_bps"].to_f / 100).round(2)}%")
        elsif pol["kind"] == "fixed"
          reserve_detail_row("Amount",   format_reserve_amount(pol["fixed_amount"], pol["currency"]))
        end
        reserve_detail_row("Hold period", "#{pol["hold_days"] || 90} days")
        reserve_detail_row("Mode",        (pol["mode"] || "live").capitalize)
        reserve_detail_row("Reason",      pol["reason"])      if pol["reason"].present?
        reserve_detail_row("Created by",  pol["created_by"])  if pol["created_by"].present?
        reserve_detail_row("Approved by", pol["approved_by"]) if pol["approved_by"].present?
      end

      if can?(:approve?, :reserve_policies) && status == "pending_approval"
        div(class: "pt-3 border-t border-gray-100") do
          a(href: approve_modal_merchant_reserve_policy_path(@app, pol["id"]),
            class: "#{BTN_SUCCESS} w-full justify-center",
            data: { turbo_frame: "modal-frame" }) do
            render UI::Icon.new(:check_circle, class: ICON_SM)
            plain "Approve policy"
          end
          p(class: "#{TYPE_CAPTION} text-center mt-2") do
            plain "Must be approved by a different ops manager (SoD)."
          end
          p(class: "#{TYPE_CAPTION} text-center mt-1") do
            plain "Reserve policy setup is independent of KYB approval."
          end
        end
      end

      if can?(:manage?, :reserve_policies) && %w[active awaiting_merchant_ack].include?(status)
        div(class: "pt-3 border-t border-gray-100") do
          a(href: deactivate_modal_merchant_reserve_policy_path(@app, pol["id"]),
            class: "#{BTN_DANGER} w-full justify-center",
            data: { turbo_frame: "modal-frame" }) do
            render UI::Icon.new(:minus, class: ICON_SM)
            plain "Deactivate policy"
          end
        end
      end
    end

    def status_banner(icon, bg_border, icon_color, text_color, message)
      div(class: "flex items-center gap-2 px-3 py-2.5 rounded-xl border #{bg_border} mb-3") do
        span(class: "flex w-4 h-4 #{icon_color} flex-shrink-0") { render UI::Icon.new(icon, class: "w-full h-full") }
        p(class: "text-[12px] font-semibold #{text_color}") { plain message }
      end
    end

    def reserve_detail_row(label, value)
      div(class: "py-2.5 flex items-center justify-between") do
        p(class: TYPE_MICRO) { plain label }
        p(class: "text-[12.5px] text-gray-700 font-medium") { plain value.to_s }
      end
    end

    def policy_kind_label(kind)
      case kind
      when "rolling" then "Rolling percentage"
      when "fixed"   then "Fixed amount"
      when "ad_hoc"  then "Ad hoc"
      else kind.to_s.humanize
      end
    end

    def format_reserve_amount(amount, currency)
      return "—" if amount.nil?
      "#{currency} #{sprintf("%.2f", amount.to_f / 100)}"
    end

    # ── Actions card ──────────────────────────────────────────────────────────

    def actions_card
      render UI::Card.new do |c|
        c.header("Actions")
        c.body do
          div(class: "flex flex-col gap-2") do
            if @app.merchant_code.present?
              ubo_block = ubo_screening_blocked?
              kyb_approve_form(blocked: ubo_block)
            elsif @app.pending?
              approve_form
              reject_form
            end
            suspend_form    if @app.approved?
            reactivate_form if @app.suspended?

            if @app.merchant_code.present?
              render UI::Button.new(variant: :secondary,
                                    href:    merchant_settlement_controls_path(@app),
                                    class:   "w-full justify-center") do
                render UI::Icon.new(:wallet, class: ICON_SM)
                plain "Settlement Controls"
              end
            end

            p(class: "#{TYPE_CAPTION} text-center mt-1") do
              plain "Status changes are logged and visible to the compliance team."
            end
          end
        end
      end
    end

    def kyb_approve_form(blocked: false)
      if blocked
        div(class: "rounded-[8px] border border-amber-200 bg-amber-50 px-3 py-[10px]") do
          div(class: "flex items-start gap-[9px]") do
            render UI::Icon.new(:alert_circle,
                                class: "w-[14px] h-[14px] text-amber-500 flex-shrink-0 mt-[1px]")
            div do
              p(class: "text-[12.5px] font-semibold text-amber-800 leading-tight") do
                plain "KYB approval blocked"
              end
              p(class: "text-[11.5px] text-amber-700 mt-[3px] leading-snug") do
                plain "One or more beneficial owners with ≥25% ownership have not been cleared by " \
                      "AML screening. Resolve all open hits before approving."
              end
            end
          end
        end
      else
        a(href: kyb_approve_modal_merchant_path(@app),
          class: "#{BTN_SUCCESS} w-full justify-center",
          data: { turbo_frame: "modal-frame" }) do
          render UI::Icon.new(:check_circle, class: ICON_SM)
          plain "Complete KYB approval"
        end
      end
    end

    def approve_form
      a(href: approve_modal_merchant_path(@app),
        class: "#{BTN_SUCCESS} w-full justify-center",
        data: { turbo_frame: "modal-frame" }) do
        render UI::Icon.new(:check_circle, class: ICON_SM)
        plain "Approve application"
      end
    end

    def reject_form
      a(href: reject_modal_merchant_path(@app),
        class: "#{BTN_DANGER} w-full justify-center",
        data: { turbo_frame: "modal-frame" }) do
        render UI::Icon.new(:x, class: ICON_SM)
        plain "Reject application"
      end
    end

    def suspend_form
      a(href: suspend_modal_merchant_path(@app),
        class: "#{BTN_DANGER} w-full justify-center",
        data: { turbo_frame: "modal-frame" }) do
        render UI::Icon.new(:archive, class: ICON_SM)
        plain "Suspend merchant"
      end
    end

    def reactivate_form
      a(href: reactivate_modal_merchant_path(@app),
        class: "#{BTN_SUCCESS} w-full justify-center",
        data: { turbo_frame: "modal-frame" }) do
        render UI::Icon.new(:check_circle, class: ICON_SM)
        plain "Reactivate merchant"
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

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

    def screening_clear?
      open_hits.empty? &&
        (@screening&.dig("subjects") || []).all? { |s|
          s["screening_status"].in?(%w[clean cleared])
        }
    end

    def screening_summary_label
      subjects = @screening&.dig("subjects") || []
      return "No subjects enrolled" if subjects.empty?
      clean = subjects.count { |s| s["screening_status"].in?(%w[clean cleared]) }
      "#{clean}/#{subjects.size} subjects clear"
    end

    # Bug fix: match by subject_id per UBO, not by type across all subjects.
    def ubos_threshold_clear?
      return false if @beneficial_owners.empty?
      flagged = @beneficial_owners.select { |u| u["ownership_bps"].to_i >= 2500 }
      flagged.all? do |u|
        subj = screening_by_subject[u["subject_ref"]]
        subj && subj["screening_status"].in?(%w[clean cleared])
      end
    end

    def ubo_screening_blocked?
      return false if @beneficial_owners.empty? || @screening.nil?
      cleared = %w[clean cleared confirmed_pep]
      @beneficial_owners.any? do |ubo|
        next false unless ubo["ownership_bps"].to_i >= 2500
        subj = screening_by_subject[ubo["subject_ref"]]
        subj && !cleared.include?(subj["screening_status"])
      end
    end

    def empty_state(icon, title, subtitle)
      div(class: "py-8 px-6 flex flex-col items-center justify-center gap-2 text-center") do
        div(class: "w-10 h-10 rounded-xl bg-gray-50 flex items-center justify-center mb-1") do
          span(class: "flex w-5 h-5 text-gray-300") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        p(class: TYPE_BODY_MD) { plain title }
        p(class: TYPE_CAPTION) { plain subtitle }
      end
    end

    def initials
      parts = @app.legal_name.to_s.split.first(2).map { |w| w[0].upcase }
      s = parts.join.first(2)
      s.empty? ? "??" : s
    end

    COUNTRY_NAMES = {
      "GH" => "Ghana", "NG" => "Nigeria", "KE" => "Kenya", "ZA" => "South Africa",
      "CI" => "Côte d'Ivoire", "SN" => "Senegal", "CM" => "Cameroon", "TZ" => "Tanzania"
    }.freeze

    def country_label
      COUNTRY_NAMES.fetch(@app.country.to_s, @app.country.to_s)
    end
  end
end
