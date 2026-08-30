# frozen_string_literal: true

module UI
  class StatusBadge < ApplicationComponent
    include UI::Theme

    DOT_COLORS = {
      "settled"            => GREEN,
      "paid"               => GREEN,
      "success"            => GREEN,
      "completed"          => GREEN,
      "approved"           => GREEN,
      "active"             => GREEN,
      "clean"              => GREEN,
      "won"                => GREEN,
      "collected"          => GREEN,
      "failed"             => RED,
      "rejected"           => RED,
      "expired"            => RED,
      "blocked"            => RED,
      "lost"               => RED,
      "true_match_blocked" => RED,
      "disputed"           => "#c2410c",
      "refunded"           => PURPLE,
      "partially_refunded" => PURPLE,
      "suspended"          => AMBER,
      "overdue"            => AMBER,
      "cleared"            => TEAL,
      "processing"         => AMBER,
      "pending"            => AMBER,
      "under_review"       => AMBER,
      "initiated"          => AMBER,
      "invited"            => AMBER,
      "confirmed_pep"      => AMBER,
      "potential_match"    => AMBER,
      "requires_action"    => AMBER,
      "cancelled"          => SUBTLE_TEXT,
      "returned"           => SUBTLE_TEXT
    }.freeze

    LABEL_MAP = {
      "paid"               => "Paid",
      "partially_refunded" => "Part. Refunded",
      "true_match_blocked" => "Blocked",
      "requires_action"    => "Action Required"
    }.freeze

    def initialize(status = nil, label: nil, **kw)
      @status = (status || kw[:status]).to_s
      @label  = label || LABEL_MAP[@status] || @status.tr("_", " ").split.map(&:capitalize).join(" ")
    end

    def view_template
      dot    = DOT_COLORS.fetch(@status, SUBTLE_TEXT)
      colors = UI::Theme.status_classes(@status)
      span(class: "inline-flex items-center gap-[5px] px-[10px] py-[3px] rounded-full text-[12px] font-medium #{colors}") do
        span(class: "w-[6px] h-[6px] rounded-full flex-shrink-0", style: "background:#{dot}")
        plain @label
      end
    end
  end
end
