# frozen_string_literal: true

module Onboarding
  module Steps
    class AgreementStep < ApplicationComponent
      include UI::Theme

      BRAND = UI::Theme::BRAND

      AGREEMENT_VERSION = "v1.0"

      TERMS = [
        { heading: "Services",              body: "Yagye processes payments on behalf of your business and will settle funds to your nominated account on the agreed schedule." },
        { heading: "Fees",                  body: "Transaction fees are charged at the rate stated in your pricing plan at the time of each transaction. Yagye reserves the right to update fees with 30 days' notice." },
        { heading: "Merchant Obligations",  body: "You agree to operate only lawful businesses, maintain accurate account information, and comply with applicable regulations in your jurisdiction." },
        { heading: "Prohibited Activities", body: "You may not use Yagye to process payments for gambling, adult content, weapons, counterfeit goods, or any activity prohibited by applicable law." },
        { heading: "Termination",           body: "Either party may terminate this agreement with 30 days' written notice. Yagye may suspend or terminate immediately for violations of these terms." },
        { heading: "Governing Law",         body: "This agreement is governed by the laws of the Republic of Ghana. Disputes shall be resolved through the courts of Ghana." }
      ].freeze

      def initialize(progress:)
        @progress  = progress
        @agreement = progress.latest_agreement
        @merchant  = progress.merchant
      end

      def view_template
        div do
          step_header

          if @agreement
            already_accepted_view
          else
            agreement_view
          end
        end
      end

      private

      def step_header
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start justify-between gap-4 mb-3") do
            div(
              class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background: rgba(61,71,245,0.08); border: 1px solid rgba(61,71,245,0.16)"
            ) do
              span(class: "flex w-[15px] h-[15px]", style: "color: #{BRAND}") do
                render UI::Icon.new(:check_circle, class: "w-full h-full")
              end
            end
            span(
              class: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0 mt-[5px]",
              style: "background: rgba(61,71,245,0.08); color: #{BRAND}"
            ) { plain "5 of 5" }
          end
          p(class: TYPE_TITLE) { plain "Service Agreement" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Review and accept the Yagye Merchant Services Agreement to complete your verification."
          end
        end
      end

      def already_accepted_view
        div(class: "px-6 py-5 space-y-5") do
          div(
            class: "rounded-xl px-5 py-4",
            style: "background: rgba(22,163,74,0.07); border: 1px solid rgba(22,163,74,0.22)"
          ) do
            div(class: "flex items-start gap-3") do
              div(
                class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
                style: "background: rgba(22,163,74,0.10); border: 1px solid rgba(22,163,74,0.20)"
              ) do
                span(class: "flex w-[14px] h-[14px]", style: "color: #16a34a") do
                  render UI::Icon.new(:check_circle, class: "w-full h-full")
                end
              end
              div do
                p(class: "text-[13px] font-semibold text-gray-900") { plain "Agreement accepted" }
                p(class: "#{TYPE_CAPTION} mt-0.5") do
                  plain "Accepted by #{@agreement["signatory_name"]} on #{format_date(@agreement["accepted_at"])}. " \
                        "Agreement #{AGREEMENT_VERSION}."
                end
              end
            end
          end

          p(class: TYPE_BODY) do
            plain "Your application is now under review. Our compliance team will process it within 1–3 business days " \
                  "and contact you at #{@agreement["signatory_email"]}."
          end
        end

        div(class: "px-6 py-4 border-t border-gray-100") do
          a(href: verify_step_path("documents"), class: BTN_SECONDARY) do
            render UI::Icon.new(:arrow_left, class: ICON_SM)
            plain "Back to Documents"
          end
        end
      end

      def agreement_view
        div(class: "px-6 py-5 space-y-5") do
          terms_scroll_box
          signatory_form
        end
      end

      def terms_scroll_box
        div(class: "rounded-xl border border-gray-100 overflow-hidden") do
          div(class: "px-5 py-3 border-b border-gray-100 bg-gray-50") do
            span(class: TYPE_HEADING) { plain "Merchant Services Agreement — #{AGREEMENT_VERSION}" }
          end

          div(class: "p-5 space-y-4 overflow-y-auto", style: "max-height: 260px") do
            TERMS.each do |term|
              div do
                p(class: "text-[13px] font-semibold text-gray-900 mb-1") { plain term[:heading] }
                p(class: "#{TYPE_CAPTION} leading-relaxed") { plain term[:body] }
              end
            end
          end
        end
      end

      def signatory_form
        form(action: submit_kyb_agreement_path, method: :post) do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "space-y-4") do
            div do
              p(class: "#{TYPE_BODY_MD} mb-0.5") { plain "Authorised Signatory Details" }
              p(class: TYPE_CAPTION) { plain "The person accepting this agreement on behalf of the business." }
            end

            div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
              text_field("signatory_name",      "Full Name",     required: true)
              text_field("signatory_email",     "Email Address", required: true, type: "email")
              text_field("signatory_phone",     "Phone Number",  type: "tel")
              text_field("signatory_job_title", "Job Title / Role")
            end

            div(class: "flex items-start gap-3 pt-1") do
              input(
                type:     "checkbox",
                id:       "agree_checkbox",
                required: true,
                class:    CHECKBOX_INPUT
              )
              label(for: "agree_checkbox", class: "text-[13px] text-gray-600 leading-snug") do
                plain "I confirm I am authorised to sign on behalf of this business and agree to the "
                span(class: "font-semibold text-gray-900") { plain "Yagye Merchant Services Agreement" }
                plain " (#{AGREEMENT_VERSION})."
              end
            end
          end

          div(class: "mt-5 pt-4 border-t border-gray-100 flex items-center justify-between") do
            a(href: verify_step_path("documents"), class: BTN_SECONDARY) do
              render UI::Icon.new(:arrow_left, class: ICON_SM)
              plain "Back"
            end
            button(type: "submit", class: BTN_PRIMARY) do
              render UI::Icon.new(:check, class: ICON_SM)
              plain "Accept & Submit"
            end
          end
        end
      end

      def text_field(name, label_text, required: false, type: "text")
        div do
          div(class: "flex items-baseline gap-1 mb-1.5") do
            label(for: name, class: "block text-[13px] font-medium text-gray-700") { plain label_text }
            sup(class: "text-red-500") { "*" } if required
          end
          input(
            type:     type,
            name:     name,
            id:       name,
            required: required,
            class:    INPUT_FIELD
          )
        end
      end

      def format_date(iso)
        return "" unless iso
        Time.parse(iso).strftime("%B %-d, %Y")
      rescue ArgumentError
        iso
      end
    end
  end
end
