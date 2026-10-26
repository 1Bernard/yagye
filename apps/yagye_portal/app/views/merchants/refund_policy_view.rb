# frozen_string_literal: true

module Merchants
  class RefundPolicyView < ApplicationComponent
    include UI::Theme

    def initialize(application:, config: {})
      @app    = application
      @config = config
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :merchants,
        title:      "Refund Policy",
        breadcrumbs: [
          { label: "Merchants",         url: merchants_path },
          { label: @app.legal_name || @app.merchant_code, url: merchant_path(@app) },
          { label: "Refund Policy" }
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
        policy_card
      end
    end

    def right_column
      div(class: "flex flex-col gap-5") do
        how_it_works_card
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def refund_window_days
      @config["refund_window_days"]&.to_s || "180"
    end

    def partial_refunds_enabled?
      val = @config["partial_refunds_enabled"]
      val.nil? ? true : val
    end

    def approval_threshold_ghs
      pesewas = @config["requires_approval_above_pesewas"]
      pesewas ? (pesewas.to_f / 100).to_s : ""
    end

    # ── Policy card ───────────────────────────────────────────────────────────

    def policy_card
      render UI::Card.new do |c|
        c.header("Refund Policy")
        c.body(padding: false) do
          form(action: merchant_refund_policy_path(@app), method: "post",
               data: { turbo: false }) do
            input(type: "hidden", name: "_method",            value: "patch")
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: "px-6 py-5 flex flex-col gap-6") do
              window_field
              partial_field
              threshold_field
            end

            div(class: "px-6 py-4 border-t border-gray-100 flex justify-end") do
              render UI::Button.new(variant: :primary, type: "submit") do
                render UI::Icon.new(:check, class: ICON_SM)
                plain "Save refund policy"
              end
            end
          end
        end
      end
    end

    def window_field
      form_field("Refund window (days)") do
        input(
          type:        "number",
          name:        "refund_window_days",
          value:       refund_window_days,
          min:         "1",
          max:         "365",
          step:        "1",
          placeholder: "180",
          class:       INPUT_FIELD
        )
        p(class: "#{TYPE_CAPTION} mt-2") do
          plain "How many days after payment a customer can request a refund. Default: 180 days."
        end
      end
    end

    def partial_field
      div do
        p(class: "#{TEXT_LABEL} mb-3") { plain "Partial refunds" }
        label(class: "flex items-center gap-3 cursor-pointer") do
          input(
            type:    "checkbox",
            name:    "partial_refunds_enabled",
            value:   "1",
            checked: partial_refunds_enabled?,
            class:   "w-4 h-4 rounded border-gray-300 accent-brand flex-shrink-0"
          )
          div do
            p(class: "text-[13px] font-semibold text-gray-800") { plain "Allow partial refunds" }
            p(class: TYPE_CAPTION) do
              plain "When disabled, only full refunds are permitted for this merchant."
            end
          end
        end
      end
    end

    def threshold_field
      form_field("Approval threshold (GHS)") do
        div(class: "relative") do
          span(class: "absolute left-4 top-1/2 -translate-y-1/2 text-[12.5px] font-semibold " \
                       "text-gray-400 pointer-events-none") { plain "GHS" }
          input(
            type:        "number",
            name:        "requires_approval_above_ghs",
            value:       approval_threshold_ghs,
            min:         "0",
            step:        "0.01",
            placeholder: "e.g. 500.00",
            class:       "#{INPUT_FIELD} !pl-14"
          )
        end
        p(class: "#{TYPE_CAPTION} mt-2") do
          plain "Refund requests at or above this amount require ops approval before dispatch. " \
                "Leave blank to auto-approve all refunds."
        end
      end
    end

    # ── Right column ──────────────────────────────────────────────────────────

    def how_it_works_card
      render UI::Card.new do |c|
        c.header("How it works")
        c.body do
          div(class: "flex flex-col gap-4") do
            info_point(
              :clock,
              "Refund window",
              "Sets how long after a payment a refund can be requested. Refunds outside this window are rejected. " \
              "180 days is a common standard."
            )
            info_point(
              :layers,
              "Partial refunds",
              "Controls whether merchants can issue refunds for a portion of the original payment. " \
              "Disabling forces full refunds only."
            )
            info_point(
              :check_circle,
              "Approval threshold",
              "Large refund requests above this amount are placed in 'pending approval' state until an ops manager " \
              "reviews and approves them. Leave blank for automatic approval of all amounts."
            )
          end
        end
      end
    end

    def info_point(icon, title, body)
      div(class: "flex items-start gap-3") do
        div(class: "w-7 h-7 rounded-lg bg-indigo-50 flex items-center justify-center flex-shrink-0 mt-[1px]") do
          span(class: "flex w-[13px] h-[13px] text-indigo-500") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div do
          p(class: "text-[12.5px] font-semibold text-gray-800 leading-tight") { plain title }
          p(class: "#{TYPE_CAPTION} mt-[3px] leading-relaxed") { plain body }
        end
      end
    end

    # ── Shared ────────────────────────────────────────────────────────────────

    def form_field(label_text, &block)
      div do
        p(class: "#{TEXT_LABEL} mb-2") { plain label_text }
        yield
      end
    end
  end
end
