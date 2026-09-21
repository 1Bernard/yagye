# frozen_string_literal: true

module Payments
  module PayoutRequests
    class ShowView < ApplicationComponent
      include UI::Theme

      def initialize(request:)
        @req = request
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title:      "Payout Request",
          breadcrumbs: [
            { label: "Payouts",          url: payouts_path },
            { label: "Payout Requests",  url: payout_requests_path },
            { label: "##{@req.id}" }
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
          details_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          review_card if helpers.policy(@req).review? && @req.pending?
          outcome_card if @req.reviewed_at.present?
        end
      end

      def hero_card
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Requested amount" }
              p(class: "#{TYPE_AMOUNT} text-gray-900") { plain @req.formatted_amount }
            end
            render UI::StatusBadge.new(status: @req.state)
          end
          div(class: "mt-4") do
            p(class: TYPE_CAPTION) { plain "Reason" }
            p(class: "#{TYPE_BODY_MD} mt-1 leading-relaxed") { plain @req.reason }
          end
        end
      end

      def details_card
        render UI::Card.new do |c|
          c.header("Request details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Request ID",    "##{@req.id}", mono: true)
              list.row("Merchant code", @req.merchant_code, mono: true)
              list.row("Requested by",  @req.requested_by, mono: true)
              list.row("Amount",        @req.formatted_amount)
              list.row("Status")         { render UI::StatusBadge.new(status: @req.state) }
              list.row("Submitted",     @req.created_at.strftime("%d %b %Y at %H:%M UTC"))
            end
          end
        end
      end

      def review_card
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-5 py-[18px] border-b border-gray-100") do
            p(class: "text-[13px] font-semibold text-gray-800") { plain "Review request" }
          end
          div(class: "px-5 py-4 flex flex-col gap-4") do
            # Note field
            div do
              label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-2") do
                plain "Note (optional)"
              end
              textarea(
                name:        "note",
                id:          "review_note",
                rows:        "3",
                placeholder: "Internal note visible to merchant if approved…",
                class:       "w-full px-4 py-3 rounded-xl border border-gray-200 text-[13px] leading-relaxed " \
                             "focus:outline-none focus:ring-2 focus:ring-brand/30 resize-none"
              )
            end

            div(class: "flex gap-2") do
              # Approve
              form(action: approve_payout_request_path(@req), method: "post", class: "flex-1") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                input(type: "hidden", name: "note",               id:    "approve_note", value: "")
                render UI::Button.new(variant: :primary, type: "submit",
                                      class: "w-full justify-center",
                                      data: { action: "click->copy-note#copy",
                                              copy_note_source_param: "review_note",
                                              copy_note_target_param: "approve_note" }) do
                  render UI::Icon.new(:check, class: ICON_SM)
                  plain "Approve"
                end
              end

              # Reject
              form(action: reject_payout_request_path(@req), method: "post", class: "flex-1") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                input(type: "hidden", name: "note",               id:    "reject_note", value: "")
                render UI::Button.new(variant: :danger, type: "submit",
                                      class: "w-full justify-center",
                                      data: { action: "click->copy-note#copy",
                                              copy_note_source_param: "review_note",
                                              copy_note_target_param: "reject_note" }) do
                  render UI::Icon.new(:x_circle, class: ICON_SM)
                  plain "Reject"
                end
              end
            end
          end
        end
      end

      def outcome_card
        color = @req.approved? ? GREEN : RED
        bg    = @req.approved? ? "#f0fdf4" : "#fef2f2"
        render UI::Card.new do |c|
          c.header("Review outcome")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Decision") { render UI::StatusBadge.new(status: @req.state) }
              list.row("Reviewed by",  @req.reviewed_by || "—", mono: true)
              list.row("Reviewed at",  @req.reviewed_at.strftime("%d %b %Y at %H:%M UTC"))
              list.row("Note",         @req.reviewer_note.presence || "—") if @req.reviewer_note.present?
            end
          end
        end
      end
    end
  end
end
