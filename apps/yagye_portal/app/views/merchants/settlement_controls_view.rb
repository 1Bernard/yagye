# frozen_string_literal: true

module Merchants
  class SettlementControlsView < ApplicationComponent
    include UI::Theme

    def initialize(application:, controls: {})
      @app      = application
      @controls = controls
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :merchants,
        title:      "Settlement Controls",
        breadcrumbs: [
          { label: "Merchants",        url: merchants_path },
          { label: @app.legal_name || @app.merchant_code, url: merchant_path(@app) },
          { label: "Settlement Controls" }
        ]
      ) do
        div(class: "max-w-2xl flex flex-col gap-5") do
          info_banner
          controls_card
        end
      end
    end

    private

    def threshold
      @controls["approval_threshold"]
    end

    def approver_codes
      Array(@controls["approver_user_codes"])
    end

    def info_banner
      div(class: "rounded-2xl px-6 py-5 flex items-start gap-4",
          style: "background:rgba(61,71,245,0.06);border:1px solid rgba(61,71,245,0.18)") do
        span(class: "flex-shrink-0 mt-[2px]") do
          render UI::Icon.new(:info_circle, class: "w-5 h-5", style: "color:#3D47F5")
        end
        div do
          p(class: "text-[13.5px] font-semibold text-gray-800 mb-1") do
            plain "How settlement controls work"
          end
          p(class: "#{TYPE_CAPTION} leading-relaxed") do
            plain "When a settlement batch exceeds the approval threshold, it must be manually approved by a listed approver before dispatch. Leave the threshold blank to auto-approve all batches."
          end
        end
      end
    end

    def controls_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Settlement Controls" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Configure approval rules for #{@app.legal_name || @app.merchant_code}."
          end
        end

        form(action: merchant_settlement_controls_path(@app), method: "post",
             data: { turbo: false }) do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          # Approval threshold
          div(class: "px-6 py-5 border-b border-gray-100") do
            label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") do
              plain "Approval threshold (GHS)"
            end
            div(class: "flex items-center gap-3") do
              div(class: "relative flex-1") do
                span(class: "absolute left-3 top-1/2 -translate-y-1/2 text-[13px] font-medium text-gray-400") { plain "GHS" }
                input(
                  type:        "number",
                  name:        "approval_threshold",
                  value:       threshold,
                  min:         "0",
                  step:        "1",
                  placeholder: "e.g. 50000",
                  class:       "w-full pl-12 pr-4 py-2.5 rounded-xl border border-gray-200 text-[13.5px] " \
                               "focus:outline-none focus:ring-2 focus:ring-brand/30 focus:border-brand/60"
                )
              end
            end
            p(class: "#{TYPE_CAPTION} mt-2") do
              plain "Batches at or above this amount require manual approval. Clear to auto-approve all."
            end
          end

          # Approver user codes
          div(class: "px-6 py-5 border-b border-gray-100") do
            label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") do
              plain "Approver user codes"
            end
            textarea(
              name:        "approver_user_codes",
              rows:        3,
              placeholder: "USR_ABC123, USR_DEF456",
              class:       "w-full px-4 py-2.5 rounded-xl border border-gray-200 text-[13.5px] " \
                           "focus:outline-none focus:ring-2 focus:ring-brand/30 focus:border-brand/60 " \
                           "font-mono resize-none"
            ) { plain approver_codes.join(", ") }
            p(class: "#{TYPE_CAPTION} mt-2") do
              plain "Comma-separated list of user codes permitted to approve settlement dispatch for this merchant."
            end

            unless approver_codes.empty?
              div(class: "mt-3 flex flex-wrap gap-2") do
                approver_codes.each do |code|
                  span(class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[11.5px] font-mono " \
                               "font-semibold bg-gray-100 text-gray-700 border border-gray-200") do
                    plain code
                  end
                end
              end
            end
          end

          # Save
          div(class: "px-6 py-4 flex justify-end") do
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:check, class: ICON_SM)
              plain "Save controls"
            end
          end
        end
      end
    end
  end
end
