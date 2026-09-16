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
        schedule_card
        balance_card
      end
    end

    private

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
