# frozen_string_literal: true

module Activity
  class IndexView < ApplicationComponent
    include UI::Theme

    DOMAIN_CFG = {
      "payment"    => { label: "Payment",    color: "#3D47F5", bg: "rgba(61,71,245,0.08)",   icon: :credit_card },
      "settlement" => { label: "Settlement", color: "#16a34a", bg: "rgba(22,163,74,0.08)",   icon: :layers },
      "dispute"    => { label: "Dispute",    color: "#dc2626", bg: "rgba(220,38,38,0.08)",   icon: :flag },
      "refund"     => { label: "Refund",     color: "#d97706", bg: "rgba(217,119,6,0.08)",   icon: :refresh },
      "account"    => { label: "Account",    color: "#6b7280", bg: "rgba(107,114,128,0.08)", icon: :shield }
    }.freeze

    EVENT_LABELS = {
      # Payment domain
      "payment.succeeded"     => "Payment succeeded",
      "payment.failed"        => "Payment failed",
      "payment.cancelled"     => "Payment cancelled",
      "payment.disputed"      => "Payment disputed",
      "payment.refunded"      => "Payment refunded",
      "payment.chargebacked"  => "Payment chargebacked",
      "payment.indeterminate" => "Payment indeterminate",
      # Settlement domain
      "settlement.created"    => "Settlement batch created",
      "settlement.settled"    => "Settlement dispatched to bank",
      # Dispute domain
      "dispute.opened"        => "Dispute opened",
      "dispute.resolved"      => "Dispute resolved",
      # Refund domain
      "refund.requested"      => "Refund initiated",
      "refund.succeeded"      => "Refund succeeded",
      "refund.failed"         => "Refund failed",
      # Account — developer actions
      "api_key.created"       => "API key created",
      "api_key.revoked"       => "API key revoked",
      "webhook.created"       => "Webhook endpoint added",
      "webhook.updated"       => "Webhook endpoint updated",
      "webhook.toggled"       => "Webhook endpoint toggled",
      "webhook.deleted"       => "Webhook endpoint removed",
      "routing_rule.created"  => "Routing configuration created",
      "routing_rule.updated"  => "Routing configuration updated",
      "routing_rule.published" => "Routing configuration published",
      # Account — payout actions
      "payout_request.submitted" => "Payout request submitted",
      "payout_request.approved"  => "Payout request approved",
      "payout_request.rejected"  => "Payout request rejected",
      # Account — refund initiation (portal-side)
      "refund.initiated"         => "Refund initiated",
      # Account — team actions (from service objects)
      "team.user_invited"         => "Team member invited",
      "team.user_suspended"       => "Team member suspended",
      "team.role_change_requested" => "Role change requested",
      "team.role_change_approved"  => "Role change approved",
      "team.role_change_rejected"  => "Role change rejected"
    }.freeze

    DOMAIN_TABS = [
      [ nil,          "All"         ],
      [ "payment",    "Payments"    ],
      [ "settlement", "Settlements" ],
      [ "dispute",    "Disputes"    ],
      [ "refund",     "Refunds"     ],
      [ "account",    "Account"     ]
    ].freeze

    def initialize(events:, domain: nil, before: nil, has_more: false, next_cursor: nil,
                   payment_map: {}, dispute_map: {})
      @events      = events
      @domain      = domain
      @before      = before
      @has_more    = has_more
      @next_cursor = next_cursor
      @payment_map = payment_map
      @dispute_map = dispute_map
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :activity,
        title:       "Activity",
        breadcrumbs: [ { label: "Activity" } ]
      ) do
        render UI::PageHeader.new(
          title:    "Activity",
          subtitle: "Events across payments, settlements, disputes, and account actions."
        )

        domain_tabs
        events_card
        load_more_row if @has_more
      end
    end

    private

    # ── Domain filter tabs ────────────────────────────────────────────────────

    def domain_tabs
      counts        = @events.group_by { |e| e["domain"] }.transform_values(&:size)
      active_domain = @domain
      total         = @events.size

      render UI::Tabs.new do |t|
        DOMAIN_TABS.each do |(val, label)|
          count = val.nil? ? total : counts[val]
          t.tab label,
                 href:   activity_path(tab: val),
                 active: active_domain == val,
                 count:  count.to_i > 0 ? count : nil
        end
      end
    end

    # ── Events card ───────────────────────────────────────────────────────────

    def events_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-4 border-b border-gray-100 flex items-center justify-between") do
          p(class: TYPE_TITLE) { plain "Events" }
          span(class: "text-[12px] font-medium text-gray-400 tabular-nums") do
            plain "#{@events.size} #{"event".pluralize(@events.size)}"
          end
        end

        if @events.empty?
          empty_state
        else
          div do
            @events.each_with_index { |event, i| event_row(event, last: i == @events.size - 1) }
          end
        end
      end
    end

    def empty_state
      div(class: "px-6 py-16 flex flex-col items-center gap-3 text-center") do
        div(class: "w-12 h-12 rounded-2xl bg-gray-100 flex items-center justify-center mb-1") do
          span(class: "w-5 h-5 text-gray-400") { render UI::Icon.new(:clock, class: "w-full h-full") }
        end
        p(class: TYPE_BODY_MD) { plain "No events yet" }
        p(class: TYPE_CAPTION) { plain "Activity will appear here as payments, settlements, and disputes are processed." }
      end
    end

    # ── Event row ─────────────────────────────────────────────────────────────

    def event_row(event, last: false)
      domain  = event["domain"] || "account"
      cfg     = DOMAIN_CFG.fetch(domain, DOMAIN_CFG["account"])
      label   = EVENT_LABELS[event["event_type"]] ||
                event["event_type"].to_s.tr("._", "  ").split.map(&:capitalize).join(" ")
      ts      = parse_ts(event["occurred_at"])
      href    = resolve_href(event)

      div(class: "flex items-start gap-4 px-6 py-[13px] #{last ? "" : "border-b border-gray-50"}") do
        # Domain icon
        div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0 mt-[1px]",
            style: "background:#{cfg[:bg]}") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0", style: "color:#{cfg[:color]}") do
            render UI::Icon.new(cfg[:icon], class: "w-full h-full")
          end
        end

        # Body
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-start justify-between gap-3") do
            div(class: "flex-1 min-w-0") do
              div(class: "flex items-center gap-2 flex-wrap") do
                span(class: "inline-flex items-center px-[7px] h-[18px] rounded-full text-[10px] font-semibold",
                     style: "background:#{cfg[:bg]};color:#{cfg[:color]}") do
                  plain cfg[:label]
                end
                p(class: "text-[12.5px] font-semibold text-gray-900 leading-tight") { plain label }
              end
              if (ref = event["resource_ref"].presence)
                if href
                  a(href: href,
                    class: "#{TYPE_MONO} text-[11px] text-[#3D47F5] hover:underline no-underline mt-[2px] block truncate") do
                    plain ref
                  end
                else
                  p(class: "#{TYPE_MONO} text-[11px] text-gray-400 mt-[2px] truncate") { plain ref }
                end
              end
            end
            span(class: "text-[11.5px] font-medium text-gray-400 tabular-nums flex-shrink-0 mt-[1px]") do
              plain ts
            end
          end
        end
      end
    end

    # ── Load more ─────────────────────────────────────────────────────────────

    def load_more_row
      div(class: "mt-3 flex justify-center") do
        a(href: activity_path(tab: @domain, before: @next_cursor),
          class: "inline-flex items-center gap-2 px-4 h-9 border border-gray-200 rounded-[10px] " \
                 "text-[12.5px] font-medium text-gray-600 bg-white no-underline hover:border-gray-400 " \
                 "transition-colors") do
          render UI::Icon.new(:clock, class: "w-3.5 h-3.5 text-gray-400")
          plain "Load older events"
        end
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def resolve_href(event)
      case event["resource_type"]
      when "payment"
        payment = @payment_map[event["resource_id"]]
        payment_path(payment) if payment
      when "dispute"
        dispute = @dispute_map[event["resource_id"]]
        dispute_path(dispute) if dispute
      end
    end

    def parse_ts(iso)
      return "—" if iso.blank?
      Time.parse(iso).strftime("%d %b, %H:%M")
    rescue ArgumentError
      "—"
    end
  end
end
