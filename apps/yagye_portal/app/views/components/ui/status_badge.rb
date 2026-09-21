# frozen_string_literal: true

module UI
  class StatusBadge < ApplicationComponent
    include UI::Theme

    LABEL_MAP = {
      "paid"               => "Paid",
      "partially_paid"     => "Partially Paid",
      "partially_refunded" => "Part. Refunded",
      "true_match_blocked" => "Blocked",
      "requires_action"    => "Action Required",
      "indeterminate"      => "Pending Verification",
      "uncollectible"      => "Uncollectible"
    }.freeze

    def initialize(status = nil, label: nil, **kw)
      @status = (status || kw[:status]).to_s
      @label  = label || LABEL_MAP[@status] || @status.tr("_", " ").split.map(&:capitalize).join(" ")
    end

    def view_template
      render UI::Chip.new(label: @label, colors: UI::Theme.status_classes(@status))
    end
  end
end
