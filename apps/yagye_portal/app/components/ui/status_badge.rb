module UI
  class StatusBadge < ApplicationComponent
    STATUS_ICONS = {
      "settled"        => "✓",
      "paid"           => "✓",
      "success"        => "✓",
      "completed"      => "✓",
      "approved"       => "✓",
      "active"         => "✓",
      "clean"          => "✓",
      "failed"         => "✗",
      "rejected"       => "✗",
      "expired"        => "✗",
      "blocked"        => "✗",
      "disputed"       => "⚑",
      "processing"     => "⚑",
      "pending"        => "⚑",
      "under_review"   => "⚑",
      "potential_match" => "⚑",
      "suspended"      => "⚑"
    }.freeze

    def initialize(status, label: nil)
      @status = status.to_s
      @label  = label || @status.humanize
    end

    def view_template
      span class: "inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium #{UI::Theme.status_classes(@status)}" do
        if (icon = STATUS_ICONS[@status])
          span class: "text-xs leading-none" do
            plain icon
          end
        end
        plain @label
      end
    end
  end
end
