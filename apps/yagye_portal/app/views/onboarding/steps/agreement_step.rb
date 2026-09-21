# frozen_string_literal: true

module Onboarding
  module Steps
    class AgreementStep < ApplicationComponent
      include UI::Theme

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
        div(class: "px-6 py-5 border-b", style: "border-color: #{colors[:border]}") do
          div(class: "flex items-center justify-between mb-1") do
            h2(class: "text-base font-semibold", style: "color: #{colors[:text_primary]}") { "Service Agreement" }
            span(class: "text-xs font-medium px-2 py-0.5 rounded-full",
                 style: "background: #{colors[:surface_subtle]}; color: #{colors[:text_muted]}") { "5 of 5" }
          end
          p(class: "text-sm", style: "color: #{colors[:text_secondary]}") do
            "Review and accept the Yagye Merchant Services Agreement to complete your verification."
          end
        end
      end

      def already_accepted_view
        div(class: "p-6 space-y-4") do
          div(class: "rounded-xl px-5 py-4",
              style: "background: #{colors[:success_subtle]}; border: 1px solid #{colors[:success]}20") do
            p(class: "text-sm font-semibold", style: "color: #{colors[:success]}") { "Agreement accepted" }
            p(class: "text-xs mt-1", style: "color: #{colors[:success]}") do
              "Accepted by #{@agreement["signatory_name"]} on #{format_date(@agreement["accepted_at"])}. " \
                "Agreement #{AGREEMENT_VERSION}."
            end
          end

          div(class: "pt-2") do
            p(class: "text-sm", style: "color: #{colors[:text_secondary]}") do
              "Your application is now under review. Our compliance team will process it within 1–3 business days " \
                "and contact you at #{@agreement["signatory_email"]}."
            end
          end

          div(class: "flex justify-start pt-2") do
            a(href: verify_step_path("documents"), class: "text-sm",
              style: "color: #{colors[:text_muted]}") { "← Back to Documents" }
          end
        end
      end

      def agreement_view
        div(class: "p-6 space-y-5") do
          terms_scroll_box
          signatory_form
        end
      end

      def terms_scroll_box
        div(class: "rounded-xl border overflow-hidden", style: "border-color: #{colors[:border]}") do
          div(class: "px-5 py-3 border-b",
              style: "background: #{colors[:surface_subtle]}; border-color: #{colors[:border]}") do
            div(class: "flex items-center justify-between") do
              span(class: "text-xs font-semibold uppercase tracking-wide",
                   style: "color: #{colors[:text_muted]}") { "Merchant Services Agreement — #{AGREEMENT_VERSION}" }
            end
          end

          div(class: "p-5 space-y-4 overflow-y-auto", style: "max-height: 280px") do
            TERMS.each do |term|
              div do
                h4(class: "text-sm font-semibold mb-1", style: "color: #{colors[:text_primary]}") { term[:heading] }
                p(class: "text-sm leading-relaxed", style: "color: #{colors[:text_secondary]}") { term[:body] }
              end
            end
          end
        end
      end

      def signatory_form
        form(action: submit_kyb_agreement_path, method: :post, class: "space-y-4") do
          csrf_token_input

          h3(class: "text-sm font-semibold", style: "color: #{colors[:text_primary]}") do
            "Authorised Signatory Details"
          end
          p(class: "text-xs -mt-2", style: "color: #{colors[:text_muted]}") do
            "The person accepting this agreement on behalf of the business."
          end

          div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
            text_field("signatory_name",      "Full Name",         required: true)
            text_field("signatory_email",     "Email Address",     required: true, type: "email")
            text_field("signatory_phone",     "Phone Number",      type: "tel")
            text_field("signatory_job_title", "Job Title / Role")
          end

          div(class: "flex items-start gap-3 pt-1") do
            input(type: "checkbox", id: "agree_checkbox", required: true,
                  class: "mt-0.5 rounded",
                  style: "color: #{colors[:brand_primary]}")
            label(for: "agree_checkbox", class: "text-sm", style: "color: #{colors[:text_secondary]}") do
              plain "I confirm I am authorised to sign on behalf of this business and agree to the "
              span(class: "font-medium", style: "color: #{colors[:brand_primary]}") do
                "Yagye Merchant Services Agreement"
              end
              plain " (#{AGREEMENT_VERSION})."
            end
          end

          div(class: "flex justify-between items-center pt-2") do
            a(href: verify_step_path("documents"), class: "text-sm",
              style: "color: #{colors[:text_muted]}") { "← Back" }
            button(
              type:  "submit",
              class: "inline-flex items-center px-5 py-2.5 rounded-lg text-sm font-medium text-white",
              style: "background: #{colors[:brand_primary]}"
            ) { "Accept Agreement & Submit" }
          end
        end
      end

      def text_field(name, label_text, required: false, type: "text")
        div do
          div(class: "flex items-baseline gap-1 mb-1.5") do
            label(for: name, class: "block text-sm font-medium",
                  style: "color: #{colors[:text_primary]}") { label_text }
            sup(class: "text-red-500") { "*" } if required
          end
          input(
            type:     type,
            name:     name,
            id:       name,
            required: required,
            class:    "w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 transition-colors"
          )
        end
      end

      def format_date(iso)
        return "" unless iso
        Time.parse(iso).strftime("%B %-d, %Y")
      rescue ArgumentError
        iso
      end

      def csrf_token_input
        input(type: "hidden", name: "authenticity_token",
              value: form_authenticity_token)
      end
    end
  end
end
