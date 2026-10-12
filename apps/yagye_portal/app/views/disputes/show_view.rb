# frozen_string_literal: true

module Disputes
  class ShowView < ApplicationComponent
    include UI::Theme

    REASON_CFG = {
      "fraud"                 => { label: "Fraudulent transaction",       badge: "badge-red"    },
      "duplicate"             => { label: "Duplicate charge",             badge: "badge-amber"  },
      "not_received"          => { label: "Product not received",         badge: "badge-violet" },
      "unrecognised"          => { label: "Unrecognised charge",          badge: "badge-blue"   },
      "unauthorized_transfer" => { label: "Unauthorized transfer",        badge: "badge-red"    },
      "network_error"         => { label: "Network / telco error",        badge: "badge-amber"  },
      "non_delivery"          => { label: "Goods / service not received", badge: "badge-violet" },
      "other"                 => { label: "Other",                        badge: "badge-gray"   }
    }.freeze

    def initialize(dispute:, can_submit_evidence: false, payment: nil)
      @dispute             = dispute
      @can_submit_evidence = can_submit_evidence
      @payment             = payment
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
            span(class: "#{reason[:badge]} #{BADGE}") { plain reason[:label] }
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

    def evidence_card
      render UI::Card.new do |c|
        c.header("Evidence", icon: :file)
        c.body(padding: false) do
          if @dispute.evidence_submitted?
            submitted_evidence_body
          elsif @can_submit_evidence
            evidence_form
          else
            no_evidence_placeholder
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
            p(class: TYPE_CAPTION) do
              plain "· #{fmt_datetime(@dispute.evidence_submitted_at)}"
            end
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
              div(class: "flex items-center gap-2 px-3 py-2 bg-gray-50 rounded-lg") do
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

    def evidence_form
      div(class: "px-6 py-5") do
        p(class: "#{TYPE_CAPTION} mb-3") do
          plain "Provide context that supports your position. Include order details, delivery confirmation, or communication with the customer."
        end
        form(action: dispute_evidence_path(@dispute), method: "post",
             enctype: "multipart/form-data") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          div(class: "space-y-3") do
            textarea(name: "evidence_text", rows: "4",
                     placeholder: "Describe the transaction and why it should be resolved in your favour...",
                     class: "w-full border border-gray-200 rounded-[10px] px-3 py-2.5 text-[13px] " \
                            "text-gray-700 bg-white outline-none focus:ring-1 resize-none " \
                            "focus:ring-[#{BRAND}] leading-relaxed")
            div(class: "border border-dashed border-gray-200 rounded-[10px] px-4 py-3 flex flex-col gap-1") do
              p(class: "#{TYPE_CAPTION} font-medium text-gray-700") { plain "Supporting documents (optional)" }
              p(class: TYPE_CAPTION) { plain "Screenshots, receipts, delivery confirmation — PDF, PNG, JPG up to 10 MB each." }
              input(type: "file", name: "evidence_files[]", multiple: true, accept: ".pdf,.png,.jpg,.jpeg",
                    class: "mt-2 text-[12px] text-gray-600 file:mr-3 file:py-1.5 file:px-3 " \
                           "file:rounded-lg file:border-0 file:text-[12px] file:font-medium " \
                           "file:bg-gray-100 file:text-gray-700 hover:file:bg-gray-200 cursor-pointer")
            end
            render UI::Button.new(variant: :primary, type: "submit") { plain "Submit evidence" }
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
          plain @dispute.open? ? "The merchant has not submitted evidence for this dispute." : "No evidence was submitted before this dispute was resolved."
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

    def detail_row_inline(label, value)
      div(class: "flex items-center justify-between") do
        p(class: TYPE_CAPTION) { plain label }
        p(class: "#{TYPE_CAPTION} text-gray-900 font-medium") { plain value.to_s }
      end
    end

    def opened_label
      fmt_datetime(@dispute.opened_at)
    end

    def resolved_label
      @dispute.resolved_at ? fmt_date(@dispute.resolved_at) : "Pending"
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
