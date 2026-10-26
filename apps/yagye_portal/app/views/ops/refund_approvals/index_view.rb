# frozen_string_literal: true

module Ops
  module RefundApprovals
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(refunds:)
        @refunds = refunds
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :refund_approvals,
          title:       "Refund Approvals",
          breadcrumbs: [ { label: "Refund Approvals" } ]
        ) do
          render UI::PageHeader.new(
            title:    "Pending refund approvals",
            subtitle: "Refunds above the merchant's approval threshold require ops sign-off before dispatch."
          )

          if @refunds.empty?
            empty_state
          else
            approvals_table
          end
        end
      end

      private

      def empty_state
        div(class: "py-16 text-center") do
          render UI::Icon.new(:check_circle, class: "w-10 h-10 mx-auto mb-3 text-gray-300")
          p(class: TYPE_BODY_MD) { plain "No refunds pending approval." }
        end
      end

      def approvals_table
        render UI::Datatable.new(records: @refunds,
                                 empty_message: "No pending refund approvals.") do |t|
          t.column("Refund ID") do |r|
            code(class: TYPE_MONO) { plain r["id"] }
          end

          t.column("Payment") do |r|
            code(class: TYPE_MONO) { plain r["payment_id"] }
          end

          t.column("Amount", class: "text-right tabular-nums") do |r|
            amount_pesewas = r["amount"].to_i
            currency = r["currency"] || "GHS"
            span(class: "text-[13px] font-semibold text-gray-900") do
              plain format_money(amount_pesewas, currency: currency)
            end
          end

          t.column("Reason") do |r|
            plain r["reason"].to_s.humanize
          end

          t.column("Initiated by") do |r|
            span(class: TYPE_BODY_SM) { plain r["initiated_by"] || "—" }
          end

          t.column("Submitted") do |r|
            plain fmt_date(r["inserted_at"] ? Time.parse(r["inserted_at"]) : nil)
          end

          t.actions do |r|
            # Approve button — opens a confirm modal inline
            button(
              type: "button",
              class: "#{DROPDOWN_ITEM} text-green-700",
              data: {
                controller: "confirm-action",
                confirm_action_url_value: approve_ops_refund_approval_path(r["id"]),
                confirm_action_method_value: "post",
                confirm_action_message_value: "Approve this refund of #{r["amount"].to_i / 100.0} #{r["currency"]}?"
              }
            ) do
              render UI::Icon.new(:check, class: ICON_SM)
              plain "Approve"
            end

            # Reject button
            button(
              type: "button",
              class: "#{DROPDOWN_ITEM} text-red-700",
              data: {
                controller: "confirm-action",
                confirm_action_url_value: reject_ops_refund_approval_path(r["id"]),
                confirm_action_method_value: "post",
                confirm_action_message_value: "Reject this refund request?"
              }
            ) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Reject"
            end
          end
        end
      end
    end
  end
end
