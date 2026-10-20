# frozen_string_literal: true

module Payments
  module Disputes
  class ShowView < ApplicationComponent
    include UI::Theme

    REASON_CFG = {
      "fraud"                 => { label: "Fraudulent transaction",       badge: STATUS_FAILED   },
      "duplicate"             => { label: "Duplicate charge",             badge: STATUS_WARNING  },
      "not_received"          => { label: "Product not received",         badge: STATUS_PENDING  },
      "unrecognised"          => { label: "Unrecognised charge",          badge: STATUS_INFO     },
      "unauthorized_transfer" => { label: "Unauthorized transfer",        badge: STATUS_FAILED   },
      "network_error"         => { label: "Network / telco error",        badge: STATUS_WARNING  },
      "non_delivery"          => { label: "Goods / service not received", badge: STATUS_PENDING  },
      "other"                 => { label: "Other",                        badge: STATUS_NEUTRAL  }
    }.freeze

    def initialize(dispute:, payment: nil, can_draft: false, can_approve: false, deadline_passed: false)
      @dispute         = dispute
      @payment         = payment
      @can_draft       = can_draft
      @can_approve     = can_approve
      @deadline_passed = deadline_passed
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

      div(class: "#{SURFACE_CARD} px-8 py-7") do
        div(class: "flex items-start justify-between mb-5") do
          div do
            p(class: "#{TYPE_CAPTION} mb-1") { plain "Disputed amount" }
            p(class: "#{TYPE_AMOUNT} text-gray-900") { plain @dispute.formatted_amount }
          end
          div(class: "flex flex-col items-end gap-2") do
            render UI::StatusBadge.new(status: @dispute.status)
            span(class: "#{BADGE} #{reason[:badge]}") { plain reason[:label] }
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
            list.row("Payment reference") do
              if @payment
                a(href: payment_path(@payment),
                  class: "#{TYPE_MONO} text-[11.5px] text-[#3D47F5] hover:underline no-underline") do
                  plain @dispute.payment_reference
                end
              else
                span(class: "#{TYPE_MONO} text-[11.5px]") { plain @dispute.payment_reference }
              end
            end
            list.row("Dispute reference", @dispute.reference, mono: true)
            list.row("Customer MSISDN",   @dispute.masked_msisdn)
            list.row("Network deadline",  @dispute.network_deadline.presence || "—")
            list.row("Resolved",          resolved_label)
          end
        end
      end
    end

    # ── Evidence card ─────────────────────────────────────────────────────────

    def evidence_card
      render UI::Card.new do |c|
        c.header("Evidence", icon: :file)
        c.body(padding: false) do
          case @dispute.evidence_stage
          when :submitted then submitted_evidence_body
          when :draft     then draft_pending_body
          else
            if @can_draft
              evidence_form
            elsif @deadline_passed
              deadline_passed_placeholder
            else
              no_evidence_placeholder
            end
          end
        end
      end
    end

    def submitted_evidence_body
      div(class: "px-6 py-5 flex flex-col gap-4") do
        div(class: "flex items-center gap-2") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0", style: "color:#{GREEN}") do
            render UI::Icon.new(:check_circle, class: "w-full h-full")
          end
          p(class: "text-[12.5px] font-semibold", style: "color:#{GREEN}") { plain "Evidence submitted" }
          if @dispute.evidence_submitted_at
            p(class: TYPE_CAPTION) { plain "· #{fmt_datetime(@dispute.evidence_submitted_at)}" }
          end
        end
        if @dispute.evidence_text.present?
          div(class: "bg-gray-50 rounded-xl px-4 py-3") do
            p(class: "text-[13px] text-gray-700 leading-relaxed whitespace-pre-wrap") do
              plain @dispute.evidence_text.to_s
            end
          end
        end
        if @dispute.evidence_files.attached?
          div(class: "flex flex-col gap-2") do
            p(class: "#{TYPE_CAPTION} font-medium") { plain "Attached files" }
            @dispute.evidence_files.each do |file|
              div(class: "flex items-center gap-2 px-3 py-2 bg-gray-50 rounded-xl border border-gray-100") do
                span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
                  render UI::Icon.new(:file, class: "w-full h-full")
                end
                span(class: "text-[12.5px] text-gray-700 truncate") { plain file.filename.to_s }
                span(class: TYPE_CAPTION) { plain number_to_human_size(file.byte_size) }
              end
            end
          end
        end
      end
    end

    def draft_pending_body
      div(class: "px-6 py-5 flex flex-col gap-4") do
        # Status banner
        div(class: "flex items-start gap-3 p-3 rounded-xl",
            style: "background:rgba(234,179,8,0.08);border:1px solid rgba(234,179,8,0.25)") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0 mt-px", style: "color:#{AMBER}") do
            render UI::Icon.new(:clock, class: "w-full h-full")
          end
          div do
            p(class: "text-[12.5px] font-semibold", style: "color:#92400e") { plain "Awaiting approval" }
            p(class: "text-[12px] text-amber-700 mt-px") do
              plain "Prepared #{fmt_datetime(@dispute.evidence_draft_at)}. A merchant owner must review and approve before this is sent to the network."
            end
          end
        end

        # Draft text
        if @dispute.evidence_draft_text.present?
          div(class: "bg-gray-50 rounded-xl px-4 py-3") do
            p(class: "text-[13px] text-gray-700 leading-relaxed whitespace-pre-wrap") do
              plain @dispute.evidence_draft_text.to_s
            end
          end
        end

        # Draft files
        if @dispute.evidence_draft_files.attached?
          div(class: "flex flex-col gap-2") do
            p(class: "#{TYPE_CAPTION} font-medium") { plain "Attached files" }
            @dispute.evidence_draft_files.each do |file|
              div(class: "flex items-center gap-2 px-3 py-2 bg-gray-50 rounded-xl border border-gray-100") do
                span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
                  render UI::Icon.new(:file, class: "w-full h-full")
                end
                span(class: "text-[12.5px] text-gray-700 truncate") { plain file.filename.to_s }
                span(class: TYPE_CAPTION) { plain number_to_human_size(file.byte_size) }
              end
            end
          end
        end

        # Approve / discard actions
        div(class: "flex items-center gap-3 pt-2 border-t border-gray-100") do
          if @can_approve
            form(action: approve_dispute_evidence_path(@dispute), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              render UI::Button.new(variant: :primary, type: "submit") { plain "Approve & submit" }
            end
          end
          form(action: discard_dispute_evidence_draft_path(@dispute), method: "post") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "_method", value: "delete")
            button(type: "submit",
                   class: "text-[12.5px] font-medium text-red-500 hover:text-red-700 transition-colors") do
              plain "Discard draft"
            end
          end
          unless @can_approve
            p(class: "text-[12px] text-gray-400") { plain "You cannot approve evidence you prepared." }
          end
        end
      end
    end

    def evidence_form
      div(class: "px-6 py-5",
          data: { controller: "evidence-files" }) do
        # Text
        div(class: "flex flex-col gap-1.5 mb-4") do
          label(class: TEXT_LABEL, for: "evidence_text") { plain "Description" }
          p(class: "#{FORM_HINT} mb-2") do
            plain "Provide context that supports your position. Include order details, delivery confirmation, or communication with the customer."
          end
          form(action: dispute_evidence_draft_path(@dispute), method: "post",
               enctype: "multipart/form-data", id: "evidence-form") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            div(class: "flex flex-col gap-3") do
              textarea(name: "evidence_text", id: "evidence_text", rows: "5",
                       placeholder: "Describe the transaction and why it should be resolved in your favour...",
                       class: TEXTAREA_FIELD)

              # File drop zone
              div(class: "border border-dashed border-gray-200 rounded-xl px-4 py-3 flex flex-col gap-2") do
                div(class: "flex items-center justify-between") do
                  div do
                    p(class: "#{TYPE_CAPTION} font-medium text-gray-700") { plain "Supporting documents" }
                    p(class: FORM_HINT) { plain "PDF, PNG, JPG · up to 10 MB each · optional" }
                  end
                  button(type: "button",
                         class: "text-[12px] font-medium text-[#3D47F5] hover:underline",
                         data: { action: "click->evidence-files#pick" }) do
                    plain "Choose files"
                  end
                end
                input(type: "file", name: "evidence_files[]",
                      multiple: true, accept: ".pdf,.png,.jpg,.jpeg",
                      class: "sr-only",
                      data: { evidence_files_target: "input", action: "change->evidence-files#picked" })

                # File chip list
                div(data: { evidence_files_target: "list" }, class: "flex flex-col gap-1.5 mt-1")
                p(class: "text-[11.5px] text-gray-400 mt-1",
                  data: { evidence_files_target: "empty" }) { plain "No files chosen" }
              end

              div(class: "flex items-center gap-3 pt-1") do
                render UI::Button.new(variant: :primary, type: "submit", form: "evidence-form") do
                  plain "Save draft"
                end
                p(class: FORM_HINT) { plain "A merchant owner will review before this is sent to the network." }
              end
            end
          end
        end
      end
    end

    def no_evidence_placeholder
      div(class: "py-10 px-6 flex flex-col items-center justify-center gap-[10px] text-center") do
        div(class: "w-11 h-11 rounded-xl icon-brand flex items-center justify-center mb-1") do
          span(class: "flex w-[22px] h-[22px]") do
            render UI::Icon.new(:file, class: "w-full h-full")
          end
        end
        p(class: TYPE_BODY_MD) { plain "No evidence submitted" }
        p(class: TYPE_CAPTION) do
          plain @dispute.open? ? "No evidence has been prepared for this dispute yet." : "No evidence was submitted before this dispute was resolved."
        end
      end
    end

    def deadline_passed_placeholder
      div(class: "py-10 px-6 flex flex-col items-center justify-center gap-[10px] text-center") do
        div(class: "w-11 h-11 rounded-xl flex items-center justify-center mb-1",
            style: "background:rgba(220,38,38,0.08);border:1px solid rgba(220,38,38,0.20)") do
          span(class: "flex w-[22px] h-[22px]", style: "color:#{RED}") do
            render UI::Icon.new(:clock, class: "w-full h-full")
          end
        end
        p(class: TYPE_BODY_MD) { plain "Submission window closed" }
        p(class: TYPE_CAPTION) { plain "The network deadline has passed. No further evidence can be submitted." }
      end
    end

    # ── Timeline ──────────────────────────────────────────────────────────────

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

    def build_timeline
      events = []
      events << [ "Dispute opened", opened_label, "#d97706" ] if @dispute.opened_at

      if @dispute.evidence_draft_at
        events << [ "Evidence draft saved", fmt_datetime(@dispute.evidence_draft_at), BRAND ]
      end

      if @dispute.evidence_submitted_at
        events << [ "Evidence submitted", fmt_datetime(@dispute.evidence_submitted_at), BRAND ]
      end

      if %w[under_review won lost closed].include?(@dispute.status)
        events << [ "Under review", "Assigned to compliance", BRAND ]
      end

      if @dispute.network_deadline.present?
        deadline = Date.parse(@dispute.network_deadline) rescue nil
        if deadline && deadline < Date.current && @dispute.resolved_at.nil?
          events << [ "Deadline passed", "Response was due #{fmt_date(deadline)}", RED ]
        end
      end

      if @dispute.resolved_at
        events << [ "Resolved — #{@dispute.status.capitalize}", resolved_label,
                    @dispute.status == "won" ? GREEN : RED ]
      end

      events = [ [ "Dispute opened", opened_label, "#d97706" ] ] if events.empty?
      events
    end

    # ── Right column ──────────────────────────────────────────────────────────

    def right_column
      div(class: "flex flex-col gap-4") do
        status_card
        sla_card if @dispute.network_deadline.present?
        ops_actions_card if current_user&.internal_staff?
      end
    end

    def status_card
      render UI::Card.new do |c|
        c.header("Dispute status")
        c.body(padding: false) do
          render UI::DetailList.new do |list|
            list.row("Status") { render UI::StatusBadge.new(status: @dispute.status) }
            list.row("Opened",   opened_label)   if @dispute.opened_at
            list.row("Resolved", resolved_label) if @dispute.resolved_at
          end
        end
      end
    end

    def sla_card
      return unless @dispute.network_deadline.present?

      deadline = Date.parse(@dispute.network_deadline) rescue nil
      return unless deadline

      days = (deadline - Date.current).to_i

      border_cls, icon_color, title_cls, body_cls, title, body =
        if days < 0
          [ "border-red-200",    RED,   "text-red-800",    "text-red-600",
           "Deadline passed",   "Response was due #{fmt_date(deadline)} — #{days.abs} day#{'s' if days.abs != 1} ago" ]
        elsif days == 0
          [ "border-red-200",    RED,   "text-red-800",    "text-red-600",
           "Respond today",     "Deadline: #{fmt_date(deadline)}" ]
        elsif days == 1
          [ "border-red-200",    RED,   "text-red-800",    "text-red-600",
           "Respond tomorrow",  "Deadline: #{fmt_date(deadline)}" ]
        elsif days <= 2
          [ "border-red-200",    RED,   "text-red-800",    "text-red-600",
           "#{days} days left", "Deadline: #{fmt_date(deadline)}" ]
        elsif days <= 6
          [ "border-yellow-200", AMBER, "text-amber-800",  "text-amber-600",
           "#{days} days left", "Deadline: #{fmt_date(deadline)}" ]
        else
          [ "border-green-200",  GREEN, "text-green-800",  "text-green-600",
           "#{days} days left", "Deadline: #{fmt_date(deadline)}" ]
        end

      div(class: "bg-white #{border_cls} rounded-2xl px-[18px] py-4 border") do
        div(class: "flex items-center gap-2 mb-2") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0", style: "color:#{icon_color}") do
            render UI::Icon.new(:clock, class: "w-full h-full")
          end
          p(class: "text-[12.5px] font-bold #{title_cls}") { plain title }
        end
        p(class: "text-[11.5px] #{body_cls}") { plain body }
      end
    end

    def ops_actions_card
      return unless @dispute.open?

      render UI::Card.new do |c|
        c.header("Ops actions")
        c.body do
          div(class: "flex flex-col gap-2") do
            a(href: resolve_confirm_modal_dispute_path(@dispute, outcome: "won"),
              class: "#{BTN_SECONDARY} w-full justify-center",
              data: { turbo_frame: "modal-frame" }) do
              plain "Mark as won"
            end
            a(href: resolve_confirm_modal_dispute_path(@dispute, outcome: "lost"),
              class: "#{BTN_DANGER} w-full justify-center",
              data: { turbo_frame: "modal-frame" }) do
              plain "Mark as lost"
            end
          end
        end
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def opened_label  = fmt_datetime(@dispute.opened_at)
    def resolved_label = @dispute.resolved_at ? fmt_date(@dispute.resolved_at) : "Pending"
  end
  end
end
