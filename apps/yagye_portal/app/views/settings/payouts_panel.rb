# frozen_string_literal: true

module Settings
  class PayoutsPanel < ApplicationComponent
    include UI::Theme

    WEEKDAY_NAMES = %w[_ Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze

    NETWORK_LABELS = {
      "mtn"        => "MTN Mobile Money",
      "telecel"    => "Telecel Cash",
      "airteltigo" => "AirtelTigo Money"
    }.freeze

    GHANA_BANKS = [
      [ "Select a bank…",                    ""        ],
      [ "Ghana Commercial Bank (GCB)",       "GCB"     ],
      [ "Absa Bank Ghana",                   "ABSA"    ],
      [ "Standard Chartered Ghana",          "SCB"     ],
      [ "Ecobank Ghana",                     "ECO"     ],
      [ "First Bank of Nigeria (FBN Ghana)", "FBN"     ],
      [ "Stanbic Bank Ghana",                "STANBIC" ],
      [ "Zenith Bank Ghana",                 "ZENITH"  ],
      [ "CalBank",                           "CAL"     ],
      [ "Republic Bank Ghana",               "RBG"     ],
      [ "Agricultural Development Bank",     "ADB"     ],
      [ "National Investment Bank",          "NIB"     ],
      [ "Universal Merchant Bank",           "UMB"     ],
      [ "First Atlantic Bank",               "FAB"     ],
      [ "OmniBSIC Bank",                     "OMNIBSIC"],
      [ "Société Générale Ghana",            "SGG"     ],
      [ "Access Bank Ghana",                 "ACCESS"  ],
      [ "Consolidated Bank Ghana",           "CBG"     ],
      [ "ARB Apex Bank",                     "ARB"     ],
      [ "Bank of Africa Ghana",              "BOA"     ],
      [ "Prudential Bank",                   "PBL"     ],
      [ "BSIC Ghana",                        "BSIC"    ],
      [ "Guaranty Trust Bank Ghana",         "GTB"     ]
    ].freeze

    def initialize(controls: {}, next_value_date: nil, unsettled_amount: 0, currency: "GHS",
                   destinations: [])
      @controls        = controls
      @next_value_date = next_value_date
      @unsettled       = unsettled_amount.to_i
      @currency        = currency
      @destinations    = destinations
    end

    def view_template
      div(class: "flex flex-col gap-5") do
        destinations_card
        schedule_card
        balance_card
      end
    end

    private

    # ── Destinations ──────────────────────────────────────────────────────────

    def destinations_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        # Header
        div(class: "px-6 py-5 border-b border-gray-100 flex items-center justify-between") do
          div do
            p(class: TYPE_TITLE) { plain "Payout Destinations" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Bank accounts and mobile wallets that receive your settled funds."
            end
          end
          if @destinations.any?
            span(class: "text-[11px] font-semibold px-2.5 py-1 rounded-full bg-green-50 text-green-700") do
              plain "#{@destinations.count} #{@destinations.count == 1 ? 'account' : 'accounts'}"
            end
          end
        end

        # Destination rows
        if @destinations.empty?
          div(class: "px-6 py-8 flex flex-col items-center gap-2 text-center") do
            p(class: TYPE_BODY_MD) { plain "No payout accounts yet" }
            p(class: TYPE_CAPTION) do
              plain "Add a mobile money wallet or bank account to receive your settlements."
            end
          end
        else
          div(class: "divide-y divide-gray-50") do
            @destinations.each { |dest| destination_row(dest) }
          end
        end

        # Add account — always-visible expandable at the bottom of the card
        div(class: "border-t border-gray-100") do
          details(class: "group") do
            summary(class: "px-6 py-4 cursor-pointer list-none flex items-center gap-2 " \
                           "text-[12.5px] font-semibold select-none hover:bg-gray-50 transition-colors",
                    style: "color:#{BRAND}") do
              span(class: "flex w-[13px] h-[13px]", style: "color:#{BRAND}") do
                render UI::Icon.new(:plus, class: "w-full h-full")
              end
              plain "Add account"
            end

            div(class: "px-6 pb-6") do
              add_destination_form
            end
          end
        end
      end
    end

    def destination_row(dest)
      is_default   = dest["is_default"]
      verify_state = dest["verification_state"] || "unverified"

      div(class: "px-6 py-4 flex items-center gap-4") do
        # Kind icon
        div(class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
            style: "background:#{TINT_BRAND}") do
          span(class: "flex w-[17px] h-[17px]", style: "color:#{BRAND}") do
            render UI::Icon.new(dest["kind"] == "bank" ? :bank : :smartphone, class: "w-full h-full")
          end
        end

        # Details
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 flex-wrap") do
            p(class: "text-[13px] font-semibold text-gray-800 truncate") do
              plain destination_label(dest)
            end
            if is_default
              span(class: "text-[10px] font-bold px-[6px] py-[2px] rounded-full",
                   style: "color:#{BRAND};background:#{TINT_BRAND}") { plain "Default" }
            end
            verification_badge(verify_state)
          end
          p(class: "#{TYPE_CAPTION} mt-[2px] font-mono truncate") { plain dest["masked_account"].to_s }
          if dest["added_by"].present? || dest["verified_by"].present?
            p(class: "#{TYPE_CAPTION} mt-[2px]") do
              parts = []
              parts << "Added by #{dest['added_by']}"   if dest["added_by"].present?
              parts << "Verified by #{dest['verified_by']}" if dest["verified_by"].present?
              plain parts.join(" · ")
            end
          end
        end

        # Actions
        div(class: "flex items-center gap-2 flex-shrink-0") do
          unless is_default
            form(action: settings_payout_destination_default_path(dest["id"]), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit",
                     class: "text-[12px] font-medium text-gray-500 hover:text-gray-700 " \
                            "border border-gray-200 rounded-[8px] px-3 py-1.5 bg-white " \
                            "transition-colors cursor-pointer") do
                plain "Set default"
              end
            end
          end

          form(action: settings_payout_destination_remove_path(dest["id"]), method: "post",
               data: { turbo_confirm: "Remove this account? This cannot be undone." }) do
            input(type: "hidden", name: "_method",            value: "delete")
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            button(type: "submit",
                   class: "flex items-center justify-center w-7 h-7 rounded-[8px] " \
                          "border border-gray-200 text-gray-400 hover:text-red-500 " \
                          "hover:border-red-200 bg-white transition-colors cursor-pointer") do
              span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:minus, class: "w-full h-full") }
            end
          end
        end
      end
    end

    def add_destination_form
      div(data: { controller: "tabs" }) do
        # Tab switcher
        div(class: "flex gap-1 p-1 rounded-xl bg-gray-100 mb-4") do
          [["mobile_money", "Mobile Money"], ["bank", "Bank Account"]].each_with_index do |(key, label), i|
            active = i.zero?
            button(type: "button",
                   class: "flex-1 py-2 px-4 rounded-lg text-[13px] font-medium transition-all",
                   style: active ?
                            "background:white;color:#{BRAND};box-shadow:0 1px 2px rgba(0,0,0,0.08)" :
                            "color:#6B7280",
                   data: { action: "click->tabs#switch", tabs_target: "tab", tab_key: key }) do
              plain label
            end
          end
        end

        # MoMo form
        form(action: settings_payout_destinations_path, method: "post",
             data: { tabs_target: "panel", tab_key: "mobile_money" }) do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "kind",               value: "mobile_money")
          div(class: "space-y-3") do
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Network" }
              select(name: "network",
                     class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                            "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]") do
                NETWORK_LABELS.each { |key, lbl| option(value: key) { plain lbl } }
              end
            end
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Mobile Money Number" }
              input(type: "tel", name: "msisdn", placeholder: "024 000 0000",
                    class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                           "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
            end
            render UI::Button.new(variant: :primary, type: "submit") { plain "Add account" }
          end
        end

        # Bank form
        form(action: settings_payout_destinations_path, method: "post",
             class: "hidden",
             data: { tabs_target: "panel", tab_key: "bank" }) do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "kind",               value: "bank")
          div(class: "space-y-3") do
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Bank" }
              select(name: "bank_code",
                     class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                            "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}] cursor-pointer") do
                GHANA_BANKS.each { |(lbl, val)| option(value: val) { plain lbl } }
              end
            end
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Account Number" }
              input(type: "text", name: "account_number", placeholder: "1234567890",
                    class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                           "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
            end
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Account Name" }
              input(type: "text", name: "account_name", placeholder: "Business name on account",
                    class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                           "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
            end
            render UI::Button.new(variant: :primary, type: "submit") { plain "Add account" }
          end
        end
      end
    end

    def verification_badge(state)
      color, bg, label = case state
                         when "verified"           then [GREEN, TINT_GREEN, "Verified"]
                         when "micro_deposit_sent" then [AMBER, TINT_AMBER, "Pending verification"]
                         when "failed"             then [RED,   TINT_RED,   "Verification failed"]
                         else                           [AMBER, TINT_AMBER, "Unverified"]
                         end
      span(class: "text-[10px] font-bold px-[6px] py-[2px] rounded-full",
           style: "color:#{color};background:#{bg}") { plain label }
    end

    def destination_label(dest)
      if dest["kind"] == "mobile_money"
        NETWORK_LABELS[dest["network"]] || dest["network"] || "Mobile Money"
      else
        dest["account_name"].presence || "Bank Account"
      end
    end

    # ── Schedule ──────────────────────────────────────────────────────────────

    def frequency      = @controls["settlement_frequency"] || "daily"
    def settlement_day = @controls["settlement_day"].to_i

    def schedule_label
      case frequency
      when "weekly"
        "Every #{WEEKDAY_NAMES[settlement_day] || 'Monday'}"
      when "monthly"
        "#{settlement_day.ordinalize} of each month"
      else
        "Every business day"
      end
    end

    def schedule_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Payout Schedule" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "When your settled funds are released to your accounts."
          end
        end

        div(class: "px-6 py-5") do
          render UI::DetailList.new do |list|
            list.row("Frequency") do
              span(class: "text-[13px] font-semibold text-gray-800") { plain schedule_label }
            end
            list.row("Next expected") do
              if @next_value_date
                span(class: "text-[13px] font-semibold text-gray-800") do
                  plain @next_value_date.strftime("%d %b %Y")
                end
              else
                span(class: TYPE_CAPTION) { plain "No pending settlement" }
              end
            end
          end
        end

        div(class: "px-6 py-4 bg-gray-50 border-t border-gray-100 flex items-center gap-2") do
          render UI::Icon.new(:info_circle, class: "w-[13px] h-[13px] flex-shrink-0 text-gray-400")
          p(class: TYPE_CAPTION) do
            plain "To change your payout schedule, contact your account manager or "
            a(href: "mailto:support@yagye.com",
              class: "underline text-gray-500 hover:text-gray-700") { plain "support@yagye.com" }
            plain "."
          end
        end
      end
    end

    # ── Balance ───────────────────────────────────────────────────────────────

    def balance_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Unsettled Balance" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Funds collected and awaiting disbursement."
          end
        end

        div(class: "px-6 py-6 flex items-end gap-3") do
          p(class: "text-[32px] font-extrabold tabular-nums tracking-tight leading-none",
            style: "color:#{@unsettled.positive? ? AMBER : GREEN}") do
            plain "#{@currency} #{"%.2f" % (@unsettled / 100.0)}"
          end
          p(class: "#{TYPE_CAPTION} pb-1") { plain "awaiting next settlement" }
        end
      end
    end
  end
end
