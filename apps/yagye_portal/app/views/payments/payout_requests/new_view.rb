# frozen_string_literal: true

module Payments
  module PayoutRequests
    class NewView < ApplicationComponent
      include UI::Theme

      def initialize(unsettled_amount: 0, unsettled_currency: "GHS")
        @unsettled_amount   = unsettled_amount.to_i
        @unsettled_currency = unsettled_currency
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title:      "Request Early Payout",
          breadcrumbs: [
            { label: "Payouts", url: payouts_path },
            { label: "Request Early Payout" }
          ]
        ) do
          div(class: "max-w-xl flex flex-col gap-5") do
            context_card
            form_card
          end
        end
      end

      private

      def context_card
        return if @unsettled_amount.zero?

        amount_label = "#{@unsettled_currency} #{"%.2f" % (@unsettled_amount / 100.0)}"

        div(class: "rounded-2xl px-6 py-5 flex items-start gap-4",
            style: "background:rgba(61,71,245,0.06);border:1px solid rgba(61,71,245,0.18)") do
          span(class: "flex-shrink-0 mt-[2px]") do
            render UI::Icon.new(:info_circle, class: "w-5 h-5", style: "color:#3D47F5")
          end
          div do
            p(class: "text-[13.5px] font-semibold text-gray-800 mb-1") do
              plain "#{amount_label} available to request"
            end
            p(class: "#{TYPE_CAPTION} leading-relaxed") do
              plain "This is your current unsettled balance — funds collected but not yet disbursed. " \
                    "Leave the amount blank to request the full balance, or enter a specific amount."
            end
          end
        end
      end

      def form_card
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Early Payout Request" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Our ops team will review your request and respond within 1 business day."
            end
          end

          form(action: payout_requests_path, method: "post") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            # Amount field
            div(class: "px-6 py-5 border-b border-gray-100") do
              label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") do
                plain "Amount (#{@unsettled_currency}) — optional"
              end
              div(class: "relative max-w-xs") do
                span(class: "absolute left-3 top-1/2 -translate-y-1/2 text-[13px] font-medium text-gray-400") do
                  plain @unsettled_currency
                end
                input(
                  type:        "number",
                  name:        "amount_cents",
                  min:         "1",
                  step:        "0.01",
                  placeholder: "Leave blank for full balance",
                  class:       "w-full pl-14 pr-4 py-2.5 rounded-xl border border-gray-200 text-[13.5px] " \
                               "focus:outline-none focus:ring-2 focus:ring-brand/30 focus:border-brand/60"
                )
              end
              p(class: "#{TYPE_CAPTION} mt-2") do
                plain "Maximum: #{@unsettled_currency} #{"%.2f" % (@unsettled_amount / 100.0)}"
              end
            end

            # Reason field
            div(class: "px-6 py-5 border-b border-gray-100") do
              label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") do
                plain "Reason *"
              end
              textarea(
                name:        "reason",
                rows:        "4",
                required:    true,
                placeholder: "e.g. Urgent supplier payment due Friday — need funds two days early.",
                class:       "w-full px-4 py-3 rounded-xl border border-gray-200 text-[13.5px] leading-relaxed " \
                             "focus:outline-none focus:ring-2 focus:ring-brand/30 focus:border-brand/60 resize-none"
              )
              p(class: "#{TYPE_CAPTION} mt-2") { plain "Minimum 10 characters. Be specific — it helps ops prioritise." }
            end

            div(class: "px-6 py-4 flex items-center justify-between") do
              a(href: payouts_path, class: "text-[13px] text-gray-400 no-underline hover:text-gray-600") do
                plain "Cancel"
              end
              render UI::Button.new(variant: :primary, type: "submit") do
                render UI::Icon.new(:paper_plane, class: ICON_SM)
                plain "Submit request"
              end
            end
          end
        end
      end
    end
  end
end
