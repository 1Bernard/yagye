# frozen_string_literal: true

module UI
  class StatusBadge < ApplicationComponent
    include UI::Theme

    LABEL_MAP = {
      # Payment states
      "paid"                    => "Paid",
      "partially_paid"          => "Partially Paid",
      "partially_refunded"      => "Partial Refund",
      "requires_action"         => "Action Required",
      "indeterminate"           => "Awaiting Confirmation",
      "uncollectible"           => "Uncollectible",
      # Review / document states
      "under_review"            => "In Review",
      "pending_upload"          => "Pending",
      # Screening states — labels differ from the snake_case default
      "clean"                   => "Clear",
      "cleared"                 => "Clear",
      "confirmed_match_blocked" => "Blocked",
      "true_match_blocked"      => "Blocked",
      "confirmed_pep"           => "Confirmed PEP",
      "potential_match"         => "Potential Match",
      # Routing configuration lifecycle
      "published"               => "Published",
      "archived"                => "Archived",
      # Reconciliation break states
      "written_off"             => "Written Off",
      "investigating"           => "Investigating"
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
