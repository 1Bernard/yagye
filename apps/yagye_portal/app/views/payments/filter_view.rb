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
      [ "All methods",   "",              :layers,      "All payment channels" ],
      [ "Mobile Money",  "mobile_money",  :phone,       "MTN MoMo, Telecel, AirtelTigo" ],
      [ "Card",          "card",          :credit_card, "Visa, Mastercard debit & credit" ],
      [ "Bank Transfer", "bank_transfer", :bank,        "Direct bank rail & wire transfer" ]
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
      turbo_frame_tag "drawer-frame", class: "flex flex-col h-full overflow-hidden" do
        render UI::Drawer::Header.new(
          title: "Filter payments",
          subtitle: "Narrow by status, method or date.",
          category: "Payments",
          icon: :filter,
          palette: "brand",
          active_count: active_count
        )

        # ── Saved filters utility bar (outside form to prevent invalid nested forms) ─
        saved_filters_section if @saved_filters.any?

        # ── Filter form (GET /payments) ─────────────────────────────────────
        form(action: payments_path, method: "get",
             id: "payments-filter-form",
             class: "flex-1 overflow-y-auto") do
          input(type: "hidden", name: "q", value: @query) if @query.present?

          # Status (Chips with semantic colored dots)
          render UI::Drawer::Section.new(title: "Status", icon: :check_circle, palette: "brand", border: true) do
            render UI::Filter::ChipGroup.new(
              name: "status",
              options: STATUSES,
              selected: @status,
              status_dots: true
            )
          end

          # Payment Method (Interactive Cards) & Progressive Provider Disclosure
          render UI::Drawer::Section.new(title: "Payment method", icon: :credit_card, palette: "purple", border: true) do
            div(data: {
              controller: "filter-disclosure",
              filter_disclosure_reveal_value: "mobile_money"
            }) do
              render UI::Filter::OptionList.new(
                name: "method",
                options: METHODS,
                selected: @method,
                icon_palette: "purple",
                variant: :cards,
                data: {
                  filter_disclosure_target: "source",
                  action: "change->filter-disclosure#change"
                }
              )

              # Progressive disclosure: Provider chips revealed only for Mobile Money
              div(data: { filter_disclosure_target: "panel" },
                  class: "mt-3.5 pl-3.5 border-l-2 border-indigo-200 #{'hidden' unless @method == 'mobile_money'}") do
                p(class: "#{TYPE_MICRO} mb-2 text-indigo-500 font-semibold") { plain "Select Provider" }
                render UI::Filter::ChipGroup.new(
                  name: "provider",
                  options: PROVIDERS,
                  selected: @provider
                )
              end
            end
          end

          # Date range with presets (kept from current design)
          render UI::Drawer::Section.new(title: "Date range", icon: :calendar, palette: "amber", border: false) do
            render UI::Filter::DateRange.new(from: @from, to: @to)
          end
        end

        # Sticky footer pinned at the bottom of the drawer
        render UI::Drawer::Footer.new(
          clear_url: payments_path(@query.present? ? { q: @query } : {}),
          apply_label: active_count > 0 ? "Apply filters (#{active_count})" : "Apply filters",
          form: "payments-filter-form",
          extra_slot: -> { save_filter_section }
        )
      end
    end

    private

    def active_count
      [
        @status.presence,
        @method.presence,
        @provider.presence,
        (@from.presence || @to.presence)
      ].compact.count
    end

    def saved_filters_section
      div(class: "flex-shrink-0 px-6 py-2.5 border-b border-gray-100 bg-gray-50/70") do
        div(class: "flex items-center gap-2.5 flex-wrap") do
          div(class: "flex items-center gap-1.5 flex-shrink-0") do
            span(class: "flex w-3 h-3 text-indigo-500") do
              render UI::Icon.new(:bookmark, class: "w-full h-full")
            end
            span(class: "text-[10px] font-bold text-gray-400 uppercase tracking-wider") { plain "Saved views" }
          end
          div(class: "h-3.5 w-px bg-gray-200 flex-shrink-0")
          div(class: "flex items-center gap-1.5 flex-wrap flex-1 min-w-0") do
            @saved_filters.each do |sf|
              saved_filter_chip(sf)
            end
          end
        end
      end
    end

    def saved_filter_chip(sf)
      filter_params = sf.filters.symbolize_keys.merge(@query.present? ? { q: @query } : {})
      is_active = sf.filters.present? && sf.filters.all? { |k, v| params[k].to_s == v.to_s }

      div(class: "group inline-flex items-center gap-1.5 pl-2.5 pr-1.5 py-0.5 rounded-md border " \
                 "#{is_active ? 'border-indigo-300 bg-indigo-50 text-indigo-700 font-semibold shadow-xs' : 'border-gray-200/90 bg-white hover:border-gray-300 text-gray-700 hover:text-gray-900'} " \
                 "transition-all") do
        a(href: payments_path(filter_params),
          class: "text-[11.5px] font-medium no-underline truncate max-w-[150px] text-inherit",
          data: { turbo_frame: "_top" }) do
          plain sf.name
        end
        a(href: settings_remove_saved_filter_path(sf.id),
          data: { turbo_method: "delete", turbo_frame: "_top",
                  turbo_confirm: "Remove \"#{sf.name}\"?" },
          title: "Delete saved view",
          class: "w-3.5 h-3.5 rounded flex items-center justify-center text-gray-300 hover:text-red-500 hover:bg-red-50 cursor-pointer transition-colors p-0 no-underline") do
          span(class: "flex w-2 h-2") { render UI::Icon.new(:x, class: "w-full h-full") }
        end
      end
    end

    def save_filter_section
      div(class: "border-b border-gray-100/70 bg-white px-6 py-3",
          data: { controller: "inline-edit" }) do
        # Collapsed: "Save this view" link
        div(data: { inline_edit_target: "display" }) do
          button(type: "button",
                 class: "text-[12px] text-indigo-500 hover:text-indigo-700 transition-colors " \
                        "bg-transparent border-0 cursor-pointer p-0 font-medium inline-flex items-center gap-1.5",
                 data: { action: "click->inline-edit#edit" }) do
            span(class: "flex w-3.5 h-3.5") { render UI::Icon.new(:bookmark, class: "w-full h-full") }
            plain "Save this view"
          end
        end

        # Expanded: name input + submit
        div(hidden: true, data: { inline_edit_target: "form" }) do
          form(action: settings_saved_filters_path, method: "post",
               class: "flex items-center gap-2",
               data: { turbo_frame: "_top",
                       controller: "filter-saver",
                       action: "submit->filter-saver#beforeSubmit" }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "saved_filter[namespace]", value: "Payments")
            input(type: "hidden", name: "saved_filter[shared_with_merchant]", value: "false")
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
  end
end
