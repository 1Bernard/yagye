# frozen_string_literal: true

module Payments
  class FilterView < ApplicationComponent
    include UI::Theme

    STATUSES = [
      [ "All",        ""           ],
      [ "Paid",       "paid"       ],
      [ "Processing", "processing" ],
      [ "Failed",     "failed"     ],
      [ "Refunded",   "refunded"   ],
      [ "Disputed",   "disputed"   ]
    ].freeze

    METHODS = [
      [ "All methods",   "",               :layers       ],
      [ "Mobile Money",  "mobile_money",   :phone        ],
      [ "Card",          "card",           :credit_card  ],
      [ "Bank Transfer", "bank_transfer",  :bank         ]
    ].freeze

    PROVIDERS = [
      [ "All providers",    ""           ],
      [ "MTN MoMo",         "mtn_momo"   ],
      [ "Telecel Cash",     "telecel"    ],
      [ "AirtelTigo Money", "airteltigo" ]
    ].freeze

    def initialize(query: nil, status: nil, method: nil, provider: nil, from: nil, to: nil, saved_filters: [])
      @query         = query
      @status        = status
      @method        = method
      @provider      = provider
      @from          = from
      @to            = to
      @saved_filters = saved_filters
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE) { plain "Filter payments" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Narrow by status, method or date." }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        # ── Filter form (GET /payments) ─────────────────────────────────────
        # The save form is a sibling below — NOT nested here — to avoid invalid
        # nested <form> HTML that browsers silently discard the inner form for.
        form(action: payments_path, method: "get",
             id: "payments-filter-form",
             class: "flex flex-col flex-1 overflow-hidden") do
          input(type: "hidden", name: "q", value: @query) if @query.present?

          div(class: "flex-1 overflow-y-auto") do
            saved_filters_section if @saved_filters.any?

            # Status
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Status", :check_circle, "brand")
              div(class: "flex flex-wrap gap-2 mt-3") do
                STATUSES.each do |(lbl, val)|
                  label(class: "cursor-pointer") do
                    input(type: "radio", name: "status", value: val,
                          checked: (val == @status.to_s || (val == "" && @status.blank?)),
                          class: "sr-only peer")
                    span(class: CHIP) { plain lbl }
                  end
                end
              end
            end

            # Method
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Payment method", :credit_card, "purple")
              div(class: "mt-3 flex flex-col gap-[2px]") do
                METHODS.each do |(lbl, val, icon)|
                  label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 cursor-pointer transition-colors -mx-2") do
                    input(type: "radio", name: "method", value: val,
                          checked: (val == @method.to_s || (val == "" && @method.blank?)),
                          class: "w-[13px] h-[13px] accent-[#3D47F5] flex-shrink-0 cursor-pointer")
                    div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-purple") do
                      span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
                    end
                    span(class: TYPE_BODY_MD) { plain lbl }
                  end
                end
              end
            end

            # Provider
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Provider", :layers, "green")
              div(class: "flex flex-wrap gap-2 mt-3") do
                PROVIDERS.each do |(lbl, val)|
                  label(class: "cursor-pointer") do
                    input(type: "radio", name: "provider", value: val,
                          checked: (val == @provider.to_s || (val == "" && @provider.blank?)),
                          class: "sr-only peer")
                    span(class: CHIP) { plain lbl }
                  end
                end
              end
            end

            # Date range
            div(class: "px-6 py-5") do
              section_label("Date range", :calendar, "amber")
              div(class: "mt-3 grid grid-cols-2 gap-3") do
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "From" }
                  input(type: "date", name: "from", value: @from,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-gray-400")
                end
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "To" }
                  input(type: "date", name: "to", value: @to,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-gray-400")
                end
              end
            end
          end

          div(class: "flex-shrink-0 border-t border-gray-100 bg-white") do
            div(class: "flex items-center justify-between px-6 py-4") do
              a(href: payments_path(@query.present? ? { q: @query } : {}),
                class: "text-[12.5px] text-gray-400 hover:text-gray-700 transition-colors no-underline") do
                plain "Clear all"
              end
              button(type: "submit", class: BTN_PRIMARY) { plain "Apply filters" }
            end
          end
        end

        # ── Save filter section (POST /settings/saved-filters) ──────────────
        # Separate form — never nested inside the filter form above.
        # filter-saver Stimulus controller reads #payments-filter-form's live
        # values on submit so this captures what the user has selected, not
        # just what was in the URL when the drawer opened.
        save_filter_section
      end
    end

    private

    def saved_filters_section
      div(class: "px-6 py-4 border-b border-gray-100") do
        div(class: "flex items-center gap-2 mb-3") do
          div(class: "w-5 h-5 rounded-md bg-indigo-50 flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[10px] h-[10px] text-indigo-500") do
              render UI::Icon.new(:bookmark, class: "w-full h-full")
            end
          end
          p(class: "text-[11.5px] font-semibold text-gray-600") { plain "Saved filters" }
        end
        div(class: "flex flex-col gap-[3px]") do
          @saved_filters.each do |sf|
            saved_filter_row(sf)
          end
        end
      end
    end

    def saved_filter_row(sf)
      filter_params = sf.filters.symbolize_keys.merge(@query.present? ? { q: @query } : {})
      div(class: "group flex items-center gap-2 rounded-xl hover:bg-gray-50 -mx-2 px-2 py-[6px] transition-colors") do
        a(href: payments_path(filter_params),
          class: "flex-1 text-[12.5px] text-gray-700 font-medium no-underline truncate",
          data: { turbo_frame: "_top" }) do
          plain sf.name
        end
        form(action: settings_remove_saved_filter_path(sf.id), method: "post",
             data: { turbo_method: "delete", turbo_frame: "_top",
                     turbo_confirm: "Remove \"#{sf.name}\"?" }) do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          button(type: "submit",
                 class: "opacity-0 group-hover:opacity-100 transition-opacity flex w-5 h-5 rounded-md " \
                        "items-center justify-center text-gray-300 hover:text-red-500 hover:bg-red-50 " \
                        "border-0 bg-transparent cursor-pointer") do
            span(class: "flex w-[10px] h-[10px]") { render UI::Icon.new(:x, class: "w-full h-full") }
          end
        end
      end
    end

    def save_filter_section
      div(class: "border-t border-gray-100 bg-white px-6 py-3",
          data: { controller: "inline-edit" }) do
        # Collapsed: "＋ Save this filter" link
        div(data: { inline_edit_target: "display" }) do
          button(type: "button",
                 class: "text-[12px] text-indigo-500 hover:text-indigo-700 transition-colors " \
                        "bg-transparent border-0 cursor-pointer p-0 font-medium",
                 data: { action: "click->inline-edit#edit" }) do
            plain "＋ Save this filter"
          end
        end

        # Expanded: name input + submit — filter-saver captures live form values on submit
        div(hidden: true, data: { inline_edit_target: "form" }) do
          form(action: settings_saved_filters_path, method: "post",
               class: "flex items-center gap-2",
               data: { turbo_frame: "_top",
                       controller: "filter-saver",
                       action: "submit->filter-saver#beforeSubmit" }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "saved_filter[namespace]", value: "Payments")
            input(type: "hidden", name: "saved_filter[shared_with_merchant]", value: "false")
            # Placeholder — filter-saver populates this at submit time with live values
            div(data: { filter_saver_target: "inputs" })
            input(type: "text", name: "saved_filter[name]", placeholder: "Name this filter…",
                  required: true, autofocus: true,
                  class: "flex-1 h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                         "text-gray-700 bg-white outline-none focus:border-indigo-400")
            button(type: "submit",
                   class: "h-8 px-3 text-[12px] font-medium bg-indigo-500 text-white " \
                          "rounded-[9px] border-0 cursor-pointer hover:bg-indigo-600 transition-colors flex-shrink-0") do
              plain "Save"
            end
            button(type: "button",
                   class: "text-[12px] text-gray-400 hover:text-gray-600 transition-colors " \
                          "bg-transparent border-0 cursor-pointer p-0",
                   data: { action: "click->inline-edit#cancel" }) do
              plain "Cancel"
            end
          end
        end
      end
    end

    def section_label(text, icon, palette)
      div(class: "flex items-center gap-2") do
        div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-#{palette}") do
          span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
        end
        p(class: "text-[12px] font-semibold text-gray-700") { plain text }
      end
    end
  end
end
