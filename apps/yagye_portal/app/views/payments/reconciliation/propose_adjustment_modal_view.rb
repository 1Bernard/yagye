# frozen_string_literal: true

module Payments
  module Reconciliation
    class ProposeAdjustmentModalView < ApplicationComponent
      include UI::Theme

      RESOLUTION_CODES = [
        [ "Adjusted — ledger corrected",        "adjusted"           ],
        [ "Duplicate removed",                  "duplicate_removed"  ],
        [ "Timing — now matched",               "timing_resolved"    ],
        [ "Written off — below threshold",      "written_off"        ],
        [ "External correction by PSP",         "psp_corrected"      ]
      ].freeze

      def initialize(recon_break:)
        @break = recon_break
      end

      def view_template
        turbo_frame(id: "modal-frame") do
          div(class: MODAL_HEAD) do
            h2(class: TEXT_H2) { plain "Propose adjustment" }
            button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
              render UI::Icon.new(:x, class: ICON_SM)
            end
          end

          form(action: reconciliation_propose_adjustment_path(@break["id"]), method: "post") do
            div(class: MODAL_BODY) do
              p(class: "#{TYPE_BODY} mb-5") do
                plain "Submit an adjustment for dual-control review. A second ops user must approve before the ledger entry is posted."
              end

              div(class: "flex flex-col gap-4") do
                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5", for: "adj_amount") { plain "Adjustment amount (minor units)" }
                  input(id: "adj_amount", type: "number", name: "amount", min: "1", required: true,
                        placeholder: "e.g. 100 = GHS 1.00",
                        class: INPUT_FIELD)
                end

                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5", for: "adj_direction") { plain "Direction" }
                  select(id: "adj_direction", name: "direction", class: SELECT_FIELD) do
                    option(value: "credit_merchant") { plain "Credit merchant" }
                    option(value: "debit_merchant")  { plain "Debit merchant"  }
                    option(value: "credit_yagye")    { plain "Credit Yagye"    }
                  end
                end

                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5", for: "adj_resolution_code") { plain "Resolution code" }
                  select(id: "adj_resolution_code", name: "resolution_code", class: SELECT_FIELD) do
                    RESOLUTION_CODES.each do |(label, value)|
                      option(value: value) { plain label }
                    end
                  end
                end

                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5", for: "adj_note") { plain "Note (optional)" }
                  textarea(id: "adj_note", name: "resolution_note", rows: "3",
                           placeholder: "Describe the reason for this adjustment…",
                           class: TEXTAREA_FIELD)
                end
              end
            end

            div(class: MODAL_FOOT) do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "button", class: BTN_SECONDARY,
                     data: { action: "click->modal#close" }) { plain "Cancel" }
              button(type: "submit", class: BTN_PRIMARY) do
                render UI::Icon.new(:check, class: ICON_SM)
                plain "Submit for approval"
              end
            end
          end
        end
      end
    end
  end
end
