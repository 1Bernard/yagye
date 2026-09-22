# frozen_string_literal: true

module Merchants
  class ShowView < ApplicationComponent
    include UI::Theme

    def initialize(application:, beneficial_owners: [], documents: [], screening: nil)
      @app               = application
      @beneficial_owners = beneficial_owners
      @documents         = documents
      @screening         = screening
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
        status_card
        screening_card if @screening
        actions_card
      end
    end

    # ── Business hero card ────────────────────────────────────────────────────

    def business_card
      div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
        div(class: "flex items-center gap-4 mb-6") do
          render UI::Avatar.new(@app.legal_name&.first(2)&.upcase || "??", size: :lg)
          div do
            p(class: "text-[20px] font-bold text-gray-900") { plain @app.legal_name || "—" }
            p(class: TYPE_CAPTION) { plain @app.merchant_code }
          end
          div(class: "ml-auto") { render UI::StatusBadge.new(status: @app.status) }
        end
        render UI::DetailList.new do |list|
          list.row("Merchant code",  @app.merchant_code, mono: true)
          list.row("Country",        @app.country || "—")
          list.row("Submitted by",   @app.submitted_by_email || "—")
          list.row("Applied",        @app.last_applied_at&.strftime("%d %b %Y") || "—")
        end
      end
    end

    # ── KYB details card ──────────────────────────────────────────────────────

    def kyb_card
      render UI::Card.new do |c|
        c.header("KYB information")
        c.body(padding: false) do
          render UI::DetailList.new do |list|
            list.row("Industry",        @app.industry&.humanize || "—")
            list.row("Employee range",  @app.employee_range || "—")
            list.row("Trading name",    @app.trading_name.presence || "—")
            list.row("Reviewed by",     @app.reviewed_by || "—")
            list.row("Approved by",     @app.approved_by || "—")
            list.row("Rejected reason", @app.rejected_reason.presence || "—") if @app.rejected?
          end
        end
      end
    end

    # ── Beneficial owners card ────────────────────────────────────────────────

    def beneficial_owners_card
      render UI::Card.new do |c|
        c.header("Beneficial owners")
        c.body(padding: @beneficial_owners.empty?) do
          if @beneficial_owners.empty?
            p(class: TYPE_CAPTION) { plain "No beneficial owners recorded." }
          else
            div(class: "divide-y divide-gray-50") do
              @beneficial_owners.each { |ubo| ubo_row(ubo) }
            end
          end
        end
      end
    end

    def ubo_row(ubo)
      ownership_pct = ubo["ownership_bps"] ? "#{(ubo["ownership_bps"] / 100.0).round(1)}%" : "—"
      flagged       = ubo["ownership_bps"].to_i >= 2500

      div(class: "flex items-center justify-between px-5 py-3") do
        div(class: "flex items-center gap-3") do
          render UI::Avatar.new(ubo["subject_ref"]&.first(2)&.upcase || "??", size: :sm)
          div do
            p(class: TYPE_BODY_MD) { plain ubo["subject_ref"] || "—" }
            p(class: TYPE_CAPTION) { plain ubo["role"]&.humanize || "—" }
          end
        end
        div(class: "flex items-center gap-3") do
          span(class: "#{TYPE_BODY_MD} tabular-nums") { plain ownership_pct }
          if flagged
            span(class: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium bg-amber-50 text-amber-700") do
              plain "≥25%"
            end
          end
        end
      end
    end

    # ── KYB documents card ────────────────────────────────────────────────────

    DOCUMENT_KIND_LABELS = {
      "incorporation"    => "Certificate of Incorporation",
      "id"               => "Director ID",
      "proof_of_address" => "Proof of Address",
      "bank_confirmation" => "Bank Confirmation"
    }.freeze

    def documents_card
      render UI::Card.new do |c|
        c.header("KYB documents")
        c.body(padding: @documents.empty?) do
          if @documents.empty?
            p(class: TYPE_CAPTION) { plain "No documents uploaded." }
          else
            div(class: "divide-y divide-gray-50") do
              @documents.each { |doc| document_row(doc) }
            end
          end
        end
      end
    end

    def document_row(doc)
      label    = DOCUMENT_KIND_LABELS[doc["kind"]] || doc["kind"]&.humanize || "Document"
      verified = doc["scanned_at"].present?

      div(class: "flex items-center justify-between px-5 py-3") do
        div(class: "flex items-center gap-3") do
          span(class: "flex w-8 h-8 rounded-lg bg-gray-50 items-center justify-center flex-shrink-0") do
            render UI::Icon.new(:file, class: "w-4 h-4 text-gray-400")
          end
          div do
            p(class: TYPE_BODY_MD) { plain label }
            p(class: TYPE_CAPTION) do
              plain "Uploaded #{doc["inserted_at"] ? Time.parse(doc["inserted_at"]).strftime("%d %b %Y") : "—"}"
            end
          end
        end
        if verified
          span(class: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium bg-green-50 text-green-700") do
            render UI::Icon.new(:check_circle, class: "w-3 h-3")
            plain "Scanned"
          end
        else
          span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium bg-gray-50 text-gray-500") do
            plain "Pending scan"
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
            plain "Last updated #{@app.last_applied_at&.strftime("%d %b %Y, %H:%M") || "—"}"
          end
        end
      end
    end

    # ── AML Screening card ────────────────────────────────────────────────────

    def screening_card
      subjects   = @screening["subjects"]   || []
      open_hits  = @screening["open_hits"]  || []
      clear      = open_hits.empty?

      render UI::Card.new do |c|
        c.header("AML screening")
        c.body(padding: subjects.empty?) do
          if subjects.empty?
            p(class: TYPE_CAPTION) { plain "No subjects enrolled for screening." }
          else
            div(class: "mb-4") do
              if clear
                div(class: "flex items-center gap-2") do
                  render UI::Icon.new(:check_circle, class: "w-4 h-4 text-green-500")
                  p(class: "#{TYPE_BODY_MD} text-green-700") { plain "No open hits" }
                end
              else
                div(class: "flex items-center gap-2") do
                  render UI::Icon.new(:alert_circle, class: "w-4 h-4 text-red-500")
                  p(class: "#{TYPE_BODY_MD} text-red-700") { plain "#{open_hits.size} open #{"hit".pluralize(open_hits.size)}" }
                end
              end
            end
            render UI::DetailList.new do |list|
              subjects.each do |s|
                list.row(s["subject_type"]&.humanize || "Subject") do
                  span(class: TYPE_BODY_MD) { plain screening_status_label(s["screening_status"]) }
                end
              end
            end
          end
        end
      end
    end

    def screening_status_label(status)
      {
        "pending"                 => "Pending",
        "clean"                   => "Clear",
        "cleared"                 => "Cleared",
        "potential_match"         => "Potential match",
        "confirmed_pep"           => "Confirmed PEP",
        "confirmed_match_blocked" => "Blocked",
        "suspended"               => "Suspended"
      }.fetch(status, status&.humanize || "—")
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
              ubo_block_notice if ubo_block
            elsif @app.pending?
              approve_form
              reject_form
            end
            if @app.approved?
              suspend_form
            end
            if @app.merchant_code.present?
              render UI::Button.new(
                variant: :secondary,
                href:    merchant_settlement_controls_path(@app),
                class:   "w-full justify-center"
              ) do
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
      form(action: kyb_approve_merchant_path(@app),
           method: "post",
           data: blocked ? {} : { turbo_confirm: "Complete KYB approval? The merchant will be live and can process payments." }) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        render UI::Button.new(
          variant: blocked ? :secondary : :primary,
          type:    "submit",
          class:   "w-full justify-center",
          disabled: blocked
        ) do
          render UI::Icon.new(:check_circle, class: ICON_SM)
          plain blocked ? "KYB approval blocked" : "Complete KYB approval"
        end
      end
    end

    def ubo_block_notice
      render UI::Notice.new(
        variant: :warning,
        size:    :sm,
        title:   "UBO screening incomplete",
        body:    "One or more beneficial owners with ≥25% ownership have not been cleared by AML screening. Resolve all open hits before approving."
      )
    end

    def approve_form
      form(action: merchant_path(@app), method: "post",
           data: { turbo_confirm: "Approve this merchant application? This will create a merchant account." }) do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        input(type: "hidden", name: "status",             value: "approved")
        render UI::Button.new(variant: :primary, type: "submit", class: "w-full justify-center") do
          render UI::Icon.new(:check_circle, class: ICON_SM)
          plain "Approve application"
        end
      end
    end

    def reject_form
      form(action: merchant_path(@app), method: "post",
           data: { turbo_confirm: "Reject this merchant application? This action cannot be undone." }) do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        input(type: "hidden", name: "status",             value: "rejected")
        render UI::Button.new(variant: :danger, type: "submit", class: "w-full justify-center") do
          render UI::Icon.new(:x, class: ICON_SM)
          plain "Reject application"
        end
      end
    end

    def suspend_form
      form(action: merchant_path(@app), method: "post",
           data: { turbo_confirm: "Suspend this merchant? They will lose access to process payments." }) do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        input(type: "hidden", name: "status",             value: "suspended")
        render UI::Button.new(variant: :danger, type: "submit", class: "w-full justify-center") do
          render UI::Icon.new(:archive, class: ICON_SM)
          plain "Suspend merchant"
        end
      end
    end

    # Returns true when any ≥25% UBO's screening subject is not clean/cleared/confirmed_pep.
    # Mirror of Core's Compliance.ubo_threshold_cleared? — computed from portal-side data.
    def ubo_screening_blocked?
      return false if @beneficial_owners.empty? || @screening.nil?

      subjects = @screening["subjects"] || []
      cleared  = %w[clean cleared confirmed_pep]

      @beneficial_owners.any? do |ubo|
        next false unless ubo["ownership_bps"].to_i >= 2500

        subject = subjects.find { |s| s["subject_type"] == "beneficial_owner" }
        subject && !cleared.include?(subject["screening_status"])
      end
    end
  end
end
