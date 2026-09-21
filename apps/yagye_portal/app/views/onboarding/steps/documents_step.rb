# frozen_string_literal: true

module Onboarding
  module Steps
    class DocumentsStep < ApplicationComponent
      include UI::Theme

      DOCUMENT_KINDS = [
        { kind: "id",                       label: "Government-issued ID",       description: "Ghana Card, Passport, or Voter's ID" },
        { kind: "form_a",                   label: "Form A / Particulars of Business", description: "RGD certificate of business particulars" },
        { kind: "certificate_of_incorporation", label: "Certificate of Incorporation", description: "Company registration from RGD" },
        { kind: "business_registration",    label: "Business Registration",      description: "Certificate of registration (sole proprietorship / partnership)" },
        { kind: "tax_clearance",            label: "Tax Clearance Certificate",  description: "From Ghana Revenue Authority" },
        { kind: "proof_of_address",         label: "Proof of Address",           description: "Utility bill or bank statement — not older than 3 months" },
        { kind: "bank_statement",           label: "Bank Statement",             description: "Last 3 months — shows business name" },
        { kind: "bank_confirmation",        label: "Bank Confirmation Letter",   description: "Signed letter on bank letterhead" }
      ].freeze

      STATUS_BADGE = {
        "pending_upload" => { label: "Not uploaded", bg: "surface_subtle", color: "text_muted" },
        "uploaded"       => { label: "Uploaded",     bg: "brand_subtle",   color: "brand_primary" },
        "under_review"   => { label: "Under review", bg: "warning_subtle", color: "warning" },
        "approved"       => { label: "Approved",     bg: "success_subtle", color: "success" },
        "rejected"       => { label: "Rejected",     bg: "error_subtle",   color: "error" }
      }.freeze

      def initialize(progress:)
        @progress  = progress
        @documents = progress.documents
      end

      def view_template
        div do
          step_header
          div(class: "p-6 space-y-4") do
            DOCUMENT_KINDS.each { |d| document_row(d) }
          end
          upload_form
        end
      end

      private

      def step_header
        div(class: "px-6 py-5 border-b", style: "border-color: #{colors[:border]}") do
          div(class: "flex items-center justify-between mb-1") do
            h2(class: "text-base font-semibold", style: "color: #{colors[:text_primary]}") { "Documents" }
            span(class: "text-xs font-medium px-2 py-0.5 rounded-full",
                 style: "background: #{colors[:surface_subtle]}; color: #{colors[:text_muted]}") { "4 of 5" }
          end
          p(class: "text-sm", style: "color: #{colors[:text_secondary]}") do
            "Upload the relevant documents for your business type. At least one document is required to continue."
          end
        end
      end

      def document_row(doc_type)
        existing = @documents.find { |d| d["kind"] == doc_type[:kind] }
        status   = existing&.dig("status") || "pending_upload"
        badge    = STATUS_BADGE[status] || STATUS_BADGE["pending_upload"]

        div(class: "flex items-center justify-between p-4 rounded-xl border gap-4",
            style: "border-color: #{colors[:border]}; background: #{colors[:surface]}") do
          div(class: "flex-1 min-w-0") do
            p(class: "text-sm font-medium", style: "color: #{colors[:text_primary]}") { doc_type[:label] }
            p(class: "text-xs mt-0.5", style: "color: #{colors[:text_muted]}") { doc_type[:description] }
          end

          div(class: "flex items-center gap-3 flex-shrink-0") do
            span(class: "text-xs font-medium px-2 py-0.5 rounded-full",
                 style: "background: #{colors[badge[:bg].to_sym]}; color: #{colors[badge[:color].to_sym]}") do
              badge[:label]
            end

            if %w[pending_upload rejected].include?(status)
              button(
                type:  "button",
                class: "text-xs font-medium px-3 py-1.5 rounded-lg border transition-colors",
                style: "border-color: #{colors[:brand_primary]}; color: #{colors[:brand_primary]}",
                data: {
                  action:    "click->upload-modal#open",
                  doc_kind:  doc_type[:kind],
                  doc_label: doc_type[:label]
                }
              ) { status == "rejected" ? "Re-upload" : "Upload" }
            end
          end
        end
      end

      def upload_form
        div(class: "px-6 pb-6") do
          div(class: "flex justify-between items-center pt-4 border-t",
              style: "border-color: #{colors[:border]}") do
            a(href: verify_step_path("settlement"), class: "text-sm",
              style: "color: #{colors[:text_muted]}") { "← Back" }
            a(href: verify_step_path("agreement"),
              class: "inline-flex items-center px-5 py-2.5 rounded-lg text-sm font-medium text-white",
              style: "background: #{colors[:brand_primary]}") do
              "Continue to Agreement →"
            end
          end
        end
      end
    end
  end
end
