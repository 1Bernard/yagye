# frozen_string_literal: true

module Onboarding
  module Steps
    class DocumentsStep < ApplicationComponent
      include UI::Theme

      BRAND = UI::Theme::BRAND

      DOCUMENT_KINDS = {
        "id"                           => { label: "Government-issued ID",             description: "Ghana Card, Passport, or Voter's ID" },
        "form_a"                       => { label: "Form A / Particulars of Business", description: "RGD certificate of business particulars" },
        "certificate_of_incorporation" => { label: "Certificate of Incorporation",     description: "Company registration from RGD" },
        "business_registration"        => { label: "Business Registration",            description: "Certificate of registration (sole prop. / partnership)" },
        "tax_clearance"                => { label: "Tax Clearance Certificate",        description: "From Ghana Revenue Authority" },
        "proof_of_address"             => { label: "Proof of Address",                 description: "Utility bill or bank statement — not older than 3 months" },
        "bank_statement"               => { label: "Bank Statement",                   description: "Last 3 months — shows business name" },
        "bank_confirmation"            => { label: "Bank Confirmation Letter",         description: "Signed letter on bank letterhead" }
      }.freeze

      BUSINESS_REQUIREMENTS = {
        "sole_proprietorship" => {
          required: %w[id business_registration],
          optional: %w[form_a tax_clearance proof_of_address bank_statement]
        },
        "partnership" => {
          required: %w[id form_a],
          optional: %w[business_registration tax_clearance proof_of_address bank_statement bank_confirmation]
        },
        "llc" => {
          required: %w[id certificate_of_incorporation form_a],
          optional: %w[tax_clearance proof_of_address bank_statement bank_confirmation]
        },
        "private_limited" => {
          required: %w[id certificate_of_incorporation form_a],
          optional: %w[tax_clearance proof_of_address bank_statement bank_confirmation]
        },
        "public_limited" => {
          required: %w[id certificate_of_incorporation form_a],
          optional: %w[tax_clearance proof_of_address bank_statement bank_confirmation]
        },
        "ngo" => {
          required: %w[id certificate_of_incorporation],
          optional: %w[form_a tax_clearance proof_of_address bank_statement]
        }
      }.freeze

      DEFAULT_REQUIREMENTS = {
        required: DOCUMENT_KINDS.keys,
        optional: []
      }.freeze

      # approved > under_review > uploaded > rejected > pending_upload
      STATUS_PRIORITY = %w[pending_upload rejected uploaded under_review approved].freeze

      def initialize(progress:)
        @progress      = progress
        @documents     = progress.documents
        @business_type = progress.merchant["business_type"]
      end

      def view_template
        div do
          step_header

          div(class: "px-6 py-5 space-y-6") do
            reqs           = BUSINESS_REQUIREMENTS.fetch(@business_type.to_s, DEFAULT_REQUIREMENTS)
            required_kinds = reqs[:required]
            optional_kinds = reqs[:optional]

            doc_section("Required Documents", required_kinds, required: true)
            doc_section("Optional Documents", optional_kinds, required: false) if optional_kinds.any?
          end

          step_footer
        end
      end

      private

      # ── Section group ───────────────────────────────────────────────────────

      def doc_section(title, kinds, required:)
        present = kinds.filter_map { |k| info = DOCUMENT_KINDS[k]; [ k, info ] if info }
        return if present.empty?

        div do
          p(class: TYPE_HEADING + " mb-3") { plain title }
          div(class: "space-y-2") do
            present.each { |kind, info| document_card(kind, info, required: required) }
          end
        end
      end

      # ── Card dispatcher ─────────────────────────────────────────────────────

      def document_card(kind, info, required:)
        # If multiple records exist for the same kind (e.g. from a prior failed upload intent),
        # pick the one with the highest lifecycle status rather than the oldest-inserted.
        existing = @documents.select { |d| d["kind"] == kind }
                             .max_by { |d| STATUS_PRIORITY.index(d["status"]) || -1 }
        status   = existing&.dig("status") || "pending_upload"

        case status
        when "pending_upload", "rejected"
          upload_card(kind, info, existing, status, required: required)
        when "uploaded"
          uploaded_card(kind, info, existing, required: required)
        when "under_review", "approved"
          readonly_card(kind, info, existing, status, required: required)
        end
      end

      # ── Pending / Rejected card ─────────────────────────────────────────────

      def upload_card(kind, info, existing, status, required:)
        is_rejected = status == "rejected"

        div(
          class: "rounded-xl border overflow-hidden bg-white transition-colors duration-150 " \
                 "#{is_rejected ? 'border-red-200' : 'border-gray-200'} " \
                 "data-[dragging=true]:border-indigo-400 " \
                 "data-[dragging=true]:shadow-[0_0_0_3px_rgba(99,102,241,0.1)]",
          data: {
            controller: "doc-upload",
            action:     "dragover->doc-upload#dragover dragleave->doc-upload#dragleave drop->doc-upload#drop"
          }
        ) do
          form(
            action:  upload_kyb_document_path,
            method:  "post",
            enctype: "multipart/form-data",
            data:    { action: "submit->doc-upload#submitting" }
          ) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "kind", value: kind)
            input(
              type:   "file",
              name:   "document",
              accept: ".pdf,.jpg,.jpeg,.png,.webp",
              hidden: true,
              data:   { "doc-upload-target": "input", action: "change->doc-upload#picked" }
            )

            # Compact header row — always visible
            div(class: "flex items-center gap-3 px-4 py-3") do
              card_icon(done: false, rejected: is_rejected)
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center gap-1.5 flex-wrap") do
                  span(class: "text-[13px] font-semibold text-gray-900 leading-tight") { plain info[:label] }
                  required_badge(required)
                  span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full bg-red-50 text-red-600") { plain "Rejected" } if is_rejected
                end
                p(class: "#{TYPE_CAPTION} mt-0.5") { plain info[:description] }
              end
              button(
                type:  "button",
                class: "flex-shrink-0 #{BTN_SECONDARY} gap-1.5",
                data:  { action: "click->doc-upload#pick" }
              ) do
                span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:upload, class: "w-full h-full") }
                plain is_rejected ? "Re-upload" : "Upload"
              end
            end

            # Rejection note
            if is_rejected && existing&.dig("reviewer_notes").present?
              div(class: "mx-4 mb-3 px-3 py-2 rounded-lg bg-red-50 border border-red-100") do
                p(class: "text-[11px] font-semibold uppercase tracking-wide text-red-400") { plain "Rejection reason" }
                p(class: "text-[12px] text-red-700 mt-0.5 leading-snug") { plain existing["reviewer_notes"] }
              end
            end

            # Preview bar — animated slide-in (doc-slide + inner wrapper)
            div(class: "doc-slide", data: { "doc-upload-target": "previewSlide" }) do
              div do
                div(class: "flex items-center gap-2.5 border-t border-gray-100 px-4 py-2.5") do
                  div(class: "w-6 h-6 flex-shrink-0 rounded bg-indigo-50 border border-indigo-100 flex items-center justify-center") do
                    span(class: "flex w-[10px] h-[10px] text-indigo-500") { render UI::Icon.new(:file, class: "w-full h-full") }
                  end
                  span(
                    class: "flex-1 min-w-0 text-[12.5px] font-medium text-gray-900 truncate",
                    data:  { "doc-upload-target": "filename" }
                  ) { }
                  span(
                    class: "text-[11px] text-gray-400 flex-shrink-0 mr-1",
                    data:  { "doc-upload-target": "filesize" }
                  ) { }
                  button(
                    type:  "button",
                    class: "flex-shrink-0 p-1 rounded text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors",
                    data:  { action: "click->doc-upload#clear" }
                  ) { render UI::Icon.new(:x, class: "w-3.5 h-3.5") }
                  button(
                    type:  "submit",
                    class: "flex-shrink-0 #{BTN_PRIMARY} ml-0.5",
                    data:  { "doc-upload-target": "submitBtn" }
                  ) do
                    span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:upload, class: "w-full h-full") }
                    span(data: { "doc-upload-target": "btnLabel" }) { plain "Upload" }
                  end
                end
              end
            end
          end
        end
      end

      # ── Uploaded card (replace + delete) ───────────────────────────────────

      def uploaded_card(kind, info, existing, required:)
        date_str    = parse_date(existing&.dig("inserted_at"))
        document_id = existing&.dig("id")

        div(
          class: "rounded-xl border border-gray-200 overflow-hidden bg-white transition-colors duration-150 " \
                 "data-[dragging=true]:border-indigo-400 " \
                 "data-[dragging=true]:shadow-[0_0_0_3px_rgba(99,102,241,0.1)]",
          data: {
            controller: "doc-upload",
            action:     "dragover->doc-upload#dragover dragleave->doc-upload#dragleave drop->doc-upload#drop"
          }
        ) do
          # Uploaded info row — stays visible, not toggled
          div(class: "flex items-center gap-3 px-4 py-3") do
            card_icon(done: true)
            div(class: "flex-1 min-w-0") do
              div(class: "flex items-center gap-1.5 flex-wrap") do
                span(class: "text-[13px] font-semibold text-gray-900 leading-tight") { plain info[:label] }
                required_badge(required)
                span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full bg-blue-50 text-blue-600") { plain "Uploaded" }
              end
              p(class: "#{TYPE_CAPTION} mt-0.5") do
                plain date_str ? "Uploaded #{date_str}" : "Document uploaded"
              end
            end
            div(class: "flex items-center gap-2 flex-shrink-0") do
              button(
                type:  "button",
                class: "inline-flex items-center gap-1.5 text-[11.5px] font-medium " \
                       "text-gray-500 hover:text-gray-700 border border-gray-200 hover:border-gray-300 " \
                       "rounded-lg px-2.5 py-1.5 transition-colors",
                data:  { action: "click->doc-upload#replace" }
              ) do
                span(class: "flex w-[10px] h-[10px]") { render UI::Icon.new(:refresh, class: "w-full h-full") }
                plain "Replace"
              end
              button(
                type:  "button",
                class: "inline-flex items-center text-[11.5px] font-medium " \
                       "text-red-400 hover:text-red-600 border border-red-100 hover:border-red-300 " \
                       "rounded-lg px-2.5 py-1.5 transition-colors hover:bg-red-50",
                data:  { action: "click->doc-upload#showDelete" }
              ) { plain "Remove" }
            end
          end

          # ── Replace slide ───────────────────────────────────────────────────
          div(class: "doc-slide", data: { "doc-upload-target": "replaceSlide" }) do
            div do
              form(
                action:  upload_kyb_document_path,
                method:  "post",
                enctype: "multipart/form-data",
                data:    { action: "submit->doc-upload#submitting" }
              ) do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                input(type: "hidden", name: "kind", value: kind)
                input(
                  type:   "file",
                  name:   "document",
                  accept: ".pdf,.jpg,.jpeg,.png,.webp",
                  hidden: true,
                  data:   { "doc-upload-target": "input", action: "change->doc-upload#picked" }
                )

                # Pick prompt row — shown by default inside replace slide
                div(
                  class: "flex items-center gap-2.5 border-t border-gray-100 px-4 py-2.5",
                  data:  { "doc-upload-target": "pickRow" }
                ) do
                  div(class: "w-6 h-6 flex-shrink-0 rounded bg-gray-100 flex items-center justify-center") do
                    span(class: "flex w-[10px] h-[10px] text-gray-400") { render UI::Icon.new(:upload, class: "w-full h-full") }
                  end
                  p(class: "flex-1 #{TYPE_CAPTION}") { plain "Choose a replacement file" }
                  button(
                    type:  "button",
                    class: "text-[11.5px] font-medium text-[#3D47F5] hover:underline mr-2",
                    data:  { action: "click->doc-upload#pick" }
                  ) { plain "Browse" }
                  button(
                    type:  "button",
                    class: "text-[11.5px] font-medium text-gray-400 hover:text-gray-600",
                    data:  { action: "click->doc-upload#cancelReplace" }
                  ) { plain "Cancel" }
                end

                # File preview — animated slide-in within replace section
                div(class: "doc-slide", data: { "doc-upload-target": "previewSlide" }) do
                  div do
                    div(class: "flex items-center gap-2.5 border-t border-gray-100 px-4 py-2.5") do
                      div(class: "w-6 h-6 flex-shrink-0 rounded bg-indigo-50 border border-indigo-100 flex items-center justify-center") do
                        span(class: "flex w-[10px] h-[10px] text-indigo-500") { render UI::Icon.new(:file, class: "w-full h-full") }
                      end
                      span(
                        class: "flex-1 min-w-0 text-[12.5px] font-medium text-gray-900 truncate",
                        data:  { "doc-upload-target": "filename" }
                      ) { }
                      span(
                        class: "text-[11px] text-gray-400 flex-shrink-0 mr-1",
                        data:  { "doc-upload-target": "filesize" }
                      ) { }
                      button(
                        type:  "button",
                        class: "flex-shrink-0 p-1 rounded text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors",
                        data:  { action: "click->doc-upload#clear" }
                      ) { render UI::Icon.new(:x, class: "w-3.5 h-3.5") }
                      button(
                        type:  "submit",
                        class: "flex-shrink-0 #{BTN_PRIMARY} ml-0.5",
                        data:  { "doc-upload-target": "submitBtn" }
                      ) do
                        span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:upload, class: "w-full h-full") }
                        span(data: { "doc-upload-target": "btnLabel" }) { plain "Upload" }
                      end
                    end
                  end
                end
              end
            end
          end

          # ── Delete confirmation slide ────────────────────────────────────────
          if document_id.present?
            div(class: "doc-slide", data: { "doc-upload-target": "deleteSlide" }) do
              div do
                form(
                  action: delete_kyb_document_path(document_id: document_id),
                  method: "post",
                  class:  "flex items-center gap-3 border-t border-red-100 bg-red-50/60 px-4 py-2.5"
                ) do
                  input(type: "hidden", name: "_method", value: "delete")
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                  span(class: "flex w-[13px] h-[13px] text-red-400 flex-shrink-0") do
                    render UI::Icon.new(:alert_triangle, class: "w-full h-full")
                  end
                  p(class: "flex-1 text-[12px] text-red-700 leading-snug") do
                    plain "Remove this document? You'll need to re-upload it to continue."
                  end
                  button(
                    type:  "button",
                    class: "text-[11.5px] font-medium text-gray-400 hover:text-gray-600 mr-1 flex-shrink-0",
                    data:  { action: "click->doc-upload#cancelDelete" }
                  ) { plain "Cancel" }
                  button(
                    type:  "submit",
                    class: "flex-shrink-0 text-[11.5px] font-semibold text-red-600 " \
                           "border border-red-200 hover:border-red-400 hover:bg-red-100 " \
                           "rounded-lg px-2.5 py-1 transition-colors"
                  ) { plain "Remove" }
                end
              end
            end
          end
        end
      end

      # ── Under review / Approved card (read-only) ────────────────────────────

      def readonly_card(kind, info, existing, status, required:)
        is_approved = status == "approved"
        date_str    = parse_date(existing&.dig("inserted_at"))

        div(
          class: "rounded-xl border overflow-hidden " \
                 "#{is_approved ? 'border-green-200 bg-green-50/40' : 'border-gray-200 bg-white'}"
        ) do
          div(class: "flex items-center gap-3 px-4 py-3") do
            card_icon(done: true, approved: is_approved)
            div(class: "flex-1 min-w-0") do
              div(class: "flex items-center gap-1.5 flex-wrap") do
                span(class: "text-[13px] font-semibold text-gray-900 leading-tight") { plain info[:label] }
                required_badge(required)
                if is_approved
                  span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full bg-green-50 text-green-700") { plain "Approved" }
                else
                  span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full bg-amber-50 text-amber-700") { plain "Under review" }
                end
              end
              p(class: "#{TYPE_CAPTION} mt-0.5") do
                plain date_str ? "Uploaded #{date_str}" : "Document uploaded"
              end
            end
          end
        end
      end

      # ── Shared helpers ──────────────────────────────────────────────────────

      def card_icon(done:, rejected: false, approved: false)
        bg = (done || approved) ? "bg-green-50" : rejected ? "bg-red-50" : "bg-gray-100"

        div(class: "w-8 h-8 flex-shrink-0 rounded-lg #{bg} flex items-center justify-center") do
          if done
            color = approved ? "text-green-600" : "text-green-500"
            span(class: "flex w-[14px] h-[14px] #{color}") { render UI::Icon.new(:check_circle, class: "w-full h-full") }
          elsif rejected
            span(class: "flex w-[14px] h-[14px] text-red-400") { render UI::Icon.new(:x, class: "w-full h-full") }
          else
            span(class: "flex w-[14px] h-[14px] text-gray-400") { render UI::Icon.new(:file, class: "w-full h-full") }
          end
        end
      end

      def required_badge(required)
        if required
          span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full bg-gray-100 text-gray-500") { plain "Required" }
        else
          span(class: "text-[10px] font-medium px-[7px] py-[2px] rounded-full bg-gray-50 text-gray-400") { plain "Optional" }
        end
      end

      def parse_date(iso_string)
        return nil unless iso_string
        Date.parse(iso_string).strftime("%-d %b %Y") rescue nil
      end

      # ── Step chrome ─────────────────────────────────────────────────────────

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
            plain "Upload the required documents for your business type. At least one is needed to continue."
          end

          if @business_type.present?
            div(class: "mt-3") do
              span(class: "inline-flex items-center gap-1.5 text-[11px] font-medium " \
                          "px-[9px] py-[3px] rounded-full bg-gray-100 text-gray-600") do
                span(class: "flex w-[10px] h-[10px] text-gray-400") do
                  render UI::Icon.new(:building, class: "w-full h-full")
                end
                plain @business_type.titleize
              end
            end
          end
        end
      end

      def step_footer
        has_docs = @documents.any? { |d| %w[uploaded under_review approved].include?(d["status"]) }

        div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-between") do
          a(href: verify_step_path("settlement"), class: BTN_SECONDARY) do
            render UI::Icon.new(:arrow_left, class: ICON_SM)
            plain "Back"
          end

          if has_docs
            a(href: verify_step_path("agreement"), class: BTN_PRIMARY) do
              plain "Continue to Agreement"
              render UI::Icon.new(:arrow_right, class: ICON_SM)
            end
          else
            span(
              class: "#{BTN_PRIMARY} opacity-40 cursor-not-allowed pointer-events-none",
              title: "Upload at least one document to continue"
            ) do
              plain "Continue to Agreement"
              render UI::Icon.new(:arrow_right, class: ICON_SM)
            end
          end
        end
      end
    end
  end
end
