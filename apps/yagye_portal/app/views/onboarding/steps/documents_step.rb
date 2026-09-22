# frozen_string_literal: true

module Onboarding
  module Steps
    class DocumentsStep < ApplicationComponent
      include UI::Theme

      BRAND = UI::Theme::BRAND

      DOCUMENT_KINDS = [
        { kind: "id",                          label: "Government-issued ID",            description: "Ghana Card, Passport, or Voter's ID" },
        { kind: "form_a",                      label: "Form A / Particulars of Business", description: "RGD certificate of business particulars" },
        { kind: "certificate_of_incorporation", label: "Certificate of Incorporation",   description: "Company registration from RGD" },
        { kind: "business_registration",       label: "Business Registration",           description: "Certificate of registration (sole proprietorship / partnership)" },
        { kind: "tax_clearance",               label: "Tax Clearance Certificate",       description: "From Ghana Revenue Authority" },
        { kind: "proof_of_address",            label: "Proof of Address",                description: "Utility bill or bank statement — not older than 3 months" },
        { kind: "bank_statement",              label: "Bank Statement",                  description: "Last 3 months — shows business name" },
        { kind: "bank_confirmation",           label: "Bank Confirmation Letter",        description: "Signed letter on bank letterhead" }
      ].freeze

      STATUS_BADGE = {
        "pending_upload" => { label: "Not uploaded", cls: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full bg-gray-100 text-gray-500" },
        "uploaded"       => { label: "Uploaded",     cls: BADGE_INFO    + " text-[11px]" },
        "under_review"   => { label: "Under review", cls: BADGE_WARNING + " text-[11px]" },
        "approved"       => { label: "Approved",     cls: BADGE_SUCCESS + " text-[11px]" },
        "rejected"       => { label: "Rejected",     cls: BADGE_FAILED  + " text-[11px]" }
      }.freeze

      def initialize(progress:)
        @progress  = progress
        @documents = progress.documents
      end

      def view_template
        div do
          step_header

          div(class: "px-6 py-5 space-y-3") do
            DOCUMENT_KINDS.each { |d| document_row(d) }
          end

          step_footer
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
                render UI::Icon.new(:file, class: "w-full h-full")
              end
            end
            span(
              class: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0 mt-[5px]",
              style: "background: rgba(61,71,245,0.08); color: #{BRAND}"
            ) { plain "4 of 5" }
          end
          p(class: TYPE_TITLE) { plain "Documents" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Upload the relevant documents for your business type. At least one document is required to continue."
          end
        end
      end

      def document_row(doc_type)
        existing = @documents.find { |d| d["kind"] == doc_type[:kind] }
        status   = existing&.dig("status") || "pending_upload"
        badge    = STATUS_BADGE.fetch(status, STATUS_BADGE["pending_upload"])

        div(class: "flex items-center gap-4 px-4 py-[14px] rounded-xl border border-gray-100 " \
                   "bg-gray-50 hover:bg-white hover:border-gray-200 transition-colors") do
          div(class: "w-8 h-8 rounded-xl bg-white border border-gray-200 " \
                     "flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px] text-gray-400") do
              render UI::Icon.new(:file, class: "w-full h-full")
            end
          end

          div(class: "flex-1 min-w-0") do
            p(class: "text-[13px] font-medium text-gray-900 leading-tight") { plain doc_type[:label] }
            p(class: TYPE_CAPTION) { plain doc_type[:description] }
          end

          div(class: "flex items-center gap-2 flex-shrink-0") do
            span(class: badge[:cls]) { plain badge[:label] }

            if %w[pending_upload rejected].include?(status)
              button(
                type:  "button",
                class: BTN_SECONDARY,
                data: {
                  action:    "click->upload-modal#open",
                  doc_kind:  doc_type[:kind],
                  doc_label: doc_type[:label]
                }
              ) { plain(status == "rejected" ? "Re-upload" : "Upload") }
            end
          end
        end
      end

      def step_footer
        div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-between") do
          a(href: verify_step_path("settlement"), class: BTN_SECONDARY) do
            render UI::Icon.new(:arrow_left, class: ICON_SM)
            plain "Back"
          end
          a(href: verify_step_path("agreement"), class: BTN_PRIMARY) do
            plain "Continue to Agreement"
            render UI::Icon.new(:arrow_right, class: ICON_SM)
          end
        end
      end
    end
  end
end
