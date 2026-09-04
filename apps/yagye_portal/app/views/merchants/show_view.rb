# frozen_string_literal: true

module Merchants
  class ShowView < ApplicationComponent
    include UI::Theme

    def initialize(application:)
      @app = application
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
      end
    end

    def right_column
      div(class: "flex flex-col gap-5") do
        status_card
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

    # ── Actions card ──────────────────────────────────────────────────────────

    def actions_card
      render UI::Card.new do |c|
        c.header("Actions")
        c.body do
          div(class: "flex flex-col gap-2") do
            if @app.pending?
              approve_form
              reject_form
            elsif @app.approved?
              suspend_form
            end
            p(class: "#{TYPE_CAPTION} text-center mt-1") do
              plain "Status changes are logged and visible to the compliance team."
            end
          end
        end
      end
    end

    def approve_form
      form(action: merchant_path(@app), method: "post",
           data: { turbo_confirm: "Approve this merchant application? This will allow them to process payments." }) do
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
  end
end
