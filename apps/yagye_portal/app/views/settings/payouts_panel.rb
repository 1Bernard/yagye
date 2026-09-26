# frozen_string_literal: true

module Settings
  class PayoutsPanel < ApplicationComponent
    include UI::Theme

    WEEKDAY_NAMES = %w[_ Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze

    def initialize(controls: {}, next_value_date: nil, unsettled_amount: 0, currency: "GHS")
      @controls        = controls
      @next_value_date = next_value_date
      @unsettled       = unsettled_amount.to_i
      @currency        = currency
    end

    def view_template
      div(class: "flex flex-col gap-5") do
        destination_card
        schedule_card
        balance_card
      end
    end

    private

    NETWORKS = [
      ["MTN Mobile Money",   "mtn"],
      ["Vodafone Cash",      "vodafone"],
      ["AirtelTigo Money",   "airteltigo"]
    ].freeze

    def destination_type
      return :momo if @controls["settlement_msisdn"].present?
      return :bank if @controls["settlement_account_number"].present?
      nil
    end

    def masked_msisdn
      raw = @controls["settlement_msisdn"].to_s.gsub(/\s/, "")
      return "—" if raw.blank?
      raw.length > 6 ? "#{raw[0..2]} *** #{raw[-4..]}" : raw
    end

    def masked_account_number
      raw = @controls["settlement_account_number"].to_s
      return "—" if raw.blank?
      raw.length > 4 ? "••••#{raw[-4..]}" : raw
    end

    def destination_card
      type = destination_type

      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100 flex items-center justify-between") do
          div do
            p(class: TYPE_TITLE) { plain "Payout Destination" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Where your settled funds are disbursed." }
          end
          if type
            span(class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-green-50 text-green-700") do
              span(class: "w-1.5 h-1.5 rounded-full flex-shrink-0 bg-green-500")
              plain "Configured"
            end
          else
            span(class: "inline-flex items-center px-2.5 py-1 rounded-full text-[11px] font-semibold bg-amber-50 text-amber-700") do
              plain "Not set"
            end
          end
        end

        div(class: "px-6 py-5") do
          if type == :momo
            div(class: "flex items-center gap-3 mb-5") do
              div(class: "w-9 h-9 rounded-xl bg-gray-50 border border-gray-100 flex items-center justify-center flex-shrink-0") do
                span(class: "flex w-[17px] h-[17px] text-gray-500") do
                  render UI::Icon.new(:smartphone, class: "w-full h-full")
                end
              end
              div do
                p(class: "text-[13px] font-semibold text-gray-800") { plain "Mobile Money" }
                p(class: "text-[12px] font-mono text-gray-500 mt-px") { plain masked_msisdn }
              end
            end
          elsif type == :bank
            div(class: "flex items-center gap-3 mb-5") do
              div(class: "w-9 h-9 rounded-xl bg-gray-50 border border-gray-100 flex items-center justify-center flex-shrink-0") do
                span(class: "flex w-[17px] h-[17px] text-gray-500") do
                  render UI::Icon.new(:bank, class: "w-full h-full")
                end
              end
              div do
                p(class: "text-[13px] font-semibold text-gray-800") do
                  plain @controls["settlement_account_name"].presence || "Bank Account"
                end
                p(class: "#{TYPE_CAPTION} mt-px") do
                  plain "#{@controls['settlement_bank_code']} · #{masked_account_number}"
                end
              end
            end
          else
            p(class: "#{TYPE_CAPTION} mb-5") do
              plain "No payout destination configured. Please complete your account setup."
            end
          end

          details(class: "group") do
            summary(class: "cursor-pointer list-none flex items-center gap-1.5 text-[12.5px] font-medium " \
                           "text-[#{BRAND}] select-none hover:opacity-80") do
              span(class: "flex w-[13px] h-[13px] flex-shrink-0", style: "color:#{BRAND}") do
                render UI::Icon.new(:edit, class: "w-full h-full")
              end
              plain(type ? "Change destination" : "Set up destination")
            end

            div(class: "mt-4 pt-4 border-t border-gray-100") do
              destination_form
            end
          end
        end
      end
    end

    def destination_form
      momo_active = destination_type == :momo || destination_type.nil?

      div(data: { controller: "tabs" }) do
        div(class: "flex gap-1 p-1 rounded-xl bg-gray-100 mb-4") do
          %w[momo bank].each do |key|
            is_active = (key == "momo") == momo_active
            button(type: "button",
                   class: "flex-1 py-2 px-4 rounded-lg text-[13px] font-medium transition-all",
                   style: is_active ?
                            "background:white;color:#{BRAND};box-shadow:0 1px 2px rgba(0,0,0,0.08)" :
                            "color:#6B7280",
                   data: { action: "click->tabs#switch",
                            tabs_target: "tab",
                            tab_key: key }) do
              plain key == "momo" ? "Mobile Money" : "Bank Account"
            end
          end
        end

        form(action: settings_payout_destination_path, method: "post",
             class: momo_active ? "" : "hidden",
             data: { tabs_target: "panel", tab_key: "momo" }) do
          input(type: "hidden", name: "_method",             value: "patch")
          input(type: "hidden", name: "authenticity_token",  value: form_authenticity_token)
          div(class: "space-y-3") do
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Mobile Money Number" }
              input(type: "tel", name: "settlement_msisdn",
                    value: @controls["settlement_msisdn"],
                    placeholder: "024 000 0000",
                    class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                           "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
            end
            render UI::Button.new(variant: :primary, type: "submit") { plain "Save" }
          end
        end

        form(action: settings_payout_destination_path, method: "post",
             class: momo_active ? "hidden" : "",
             data: { tabs_target: "panel", tab_key: "bank" }) do
          input(type: "hidden", name: "_method",             value: "patch")
          input(type: "hidden", name: "authenticity_token",  value: form_authenticity_token)
          div(class: "space-y-3") do
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Bank Code" }
              input(type: "text", name: "settlement_bank_code",
                    value: @controls["settlement_bank_code"],
                    placeholder: "e.g. GCB001",
                    class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                           "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
            end
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Account Number" }
              input(type: "text", name: "settlement_account_number",
                    value: @controls["settlement_account_number"],
                    placeholder: "1234567890",
                    class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                           "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
            end
            div do
              label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "Account Name" }
              input(type: "text", name: "settlement_account_name",
                    value: @controls["settlement_account_name"],
                    placeholder: "Business name on account",
                    class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] " \
                           "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
            end
            render UI::Button.new(variant: :primary, type: "submit") { plain "Save" }
          end
        end
      end
    end

    def frequency      = @controls["settlement_frequency"] || "daily"
    def settlement_day = @controls["settlement_day"].to_i

    def schedule_label
      case frequency
      when "weekly"
        day_name = WEEKDAY_NAMES[settlement_day] || "Monday"
        "Every #{day_name}"
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
            plain "When your settled funds are released to your bank account."
          end
        end

        div(class: "px-6 py-5 flex flex-col gap-4") do
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
