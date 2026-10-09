# frozen_string_literal: true

module Dashboard
  class FeedRowComponent < ApplicationComponent
    include UI::Theme

    def initialize(payment:)
      @payment = payment
    end

    def view_template
      dot_color = case @payment.status
      when "paid"   then GREEN
      when "failed" then RED
      else               AMBER
      end

      div(class: "flex items-center gap-3 px-5 py-[10px] hover:bg-gray-50 transition-colors") do
        span(class: "w-[7px] h-[7px] rounded-full flex-shrink-0 mt-[1px]",
             style: "background:#{dot_color}")
        div(class: "flex-1 min-w-0") do
          p(class: "#{TYPE_MONO} truncate leading-snug") { plain @payment.reference.to_s }
          p(class: "#{TYPE_CAPTION} mt-[1px]")           { plain @payment.masked_msisdn }
        end
        div(class: "text-right flex-shrink-0") do
          p(class: "text-[13px] font-semibold text-gray-900 tabular-nums leading-snug") do
            plain @payment.formatted_amount
          end
          p(class: TYPE_CAPTION) { plain time_ago(@payment.created_at) }
        end
      end
    end

    private

    def time_ago(time)
      diff = Time.current - time
      case diff
      when 0..59        then "just now"
      when 60..3599     then "#{(diff / 60).to_i}m ago"
      when 3600..86_399 then "#{(diff / 3600).to_i}h ago"
      else                   time.strftime("%-d %b")
      end
    end
  end
end
