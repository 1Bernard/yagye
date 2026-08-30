# frozen_string_literal: true

module Developers
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "api_keys",  label: "API Keys" },
      { key: "webhooks",  label: "Webhooks" },
      { key: "logs",      label: "Event Logs" }
    ].freeze

    def initialize(tab: "api_keys", api_keys: [], webhooks: [], deliveries: nil, pagy: nil)
      @tab        = tab
      @api_keys   = api_keys
      @webhooks   = webhooks
      @deliveries = deliveries || []
      @pagy       = pagy
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :developers,
        title:      "Developers",
        breadcrumbs: [ { label: "Developers" } ]
      ) do
        tab_bar
        case @tab
        when "api_keys" then api_keys_panel
        when "webhooks" then webhooks_panel
        when "logs"     then logs_panel
        end
      end
    end

    private

    def tab_bar
      render UI::Tabs.new do |t|
        TABS.each do |tab|
          t.tab tab[:label],
                href: developers_path(tab: tab[:key]),
                active: @tab == tab[:key]
        end
      end
    end

    # ── API Keys panel ───────────────────────────────────────────────────────

    def api_keys_panel
      live = Current.mode == "live"

      div do
        div(style: "display:flex;align-items:center;justify-content:flex-end;margin-bottom:20px") do
          button(type: "button", class: BTN_PRIMARY,
                 onclick: "document.getElementById('generate-key-dialog').showModal()") do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "Generate Key"
          end
          generate_key_dialog(live)
        end

        test_mode_notice unless live

        render UI::Datatable.new(records: @api_keys,
                                 empty_message: "No API keys yet. Generate your first key to start integrating.") do |t|
          t.header do
            div do
              p(style: TYPE_TITLE) { "#{live ? 'Live' : 'Test'} API keys" }
              p(style: "#{TYPE_CAPTION};margin-top:2px") { "Keys are shown once at creation. Store them securely." }
            end
          end

          t.column("Name")      { |k| span(style: TYPE_BODY_MD) { k.label.presence || k.kind.capitalize } }
          t.column("Key prefix") { |k| code(style: TYPE_MONO) { k.key_prefix + "..." } }
          t.column("Created")   { |k| span(style: TYPE_CAPTION) { k.created_at.strftime("%d %b %Y") } }
          t.column("Last used") { |k| span(style: TYPE_CAPTION) { k.last_used_at&.strftime("%d %b %Y") || "Never" } }
          t.column("Status")    { |k| render UI::StatusBadge.new(status: k.active ? "active" : "revoked") }

          t.actions do |k|
            if k.active?
              form(action: developers_key_path(k.key_id), method: "post",
                   data: { turbo_confirm: "Revoke this API key? This cannot be undone." }) do
                input(type: "hidden", name: "_method",            value: "delete")
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit", class: DROPDOWN_ITEM_DANGER) do
                  render UI::Icon.new(:x, class: ICON_SM)
                  plain "Revoke"
                end
              end
            end
          end
        end
      end
    end

    def test_mode_notice
      div(style: "background:#fffbeb;border:1px solid #fde68a;border-radius:12px;padding:14px 18px;" \
                 "margin-bottom:16px;display:flex;gap:10px;align-items:flex-start") do
        span(style: "display:flex;width:16px;height:16px;color:#d97706;flex-shrink:0;margin-top:1px") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        div do
          p(style: "font-size:13px;font-weight:600;color:#92400e;margin-bottom:2px") { "Test mode" }
          p(style: "#{TYPE_CAPTION};color:#b45309") do
            "Test keys are for development only. No real money moves. " \
            "Switch to Live mode using the toggle in the sidebar to access live keys."
          end
        end
      end
    end

    # ── Webhooks panel ────────────────────────────────────────────────────────

    def webhooks_panel
      div do
        div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:20px") do
          div do
            p(style: TYPE_BODY_MD) { "Webhook endpoints" }
            p(style: TYPE_CAPTION) { "Yagye sends signed POST requests to your endpoints for each event." }
          end
          button(type: "button", class: BTN_PRIMARY,
                 onclick: "document.getElementById('add-webhook-dialog').showModal()") do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "Add Endpoint"
          end
          add_webhook_dialog
        end

        render UI::Datatable.new(records: @webhooks,
                                 empty_message: "No webhook endpoints. Add one to receive real-time payment events.") do |t|
          t.header do
            p(style: TYPE_TITLE) { "Endpoints" }
          end

          t.column("URL")     { |wh| code(style: TYPE_MONO) { wh.url } }
          t.column("Events")  { |wh| span(style: TYPE_CAPTION) { "#{Array(wh.subscribed_events).size} events" } }
          t.column("Status")  { |wh| render UI::StatusBadge.new(status: wh.active ? "active" : "suspended") }
          t.column("Created") { |wh| span(style: TYPE_CAPTION) { wh.created_at.strftime("%d %b %Y") } }

          t.actions do |wh|
            form(action: developers_webhook_path(wh.endpoint_id), method: "post",
                 data: { turbo_confirm: "Remove this webhook endpoint?" }) do
              input(type: "hidden", name: "_method",            value: "delete")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit", class: DROPDOWN_ITEM_DANGER) do
                render UI::Icon.new(:x, class: ICON_SM)
                plain "Remove"
              end
            end
            form(action: test_developers_webhook_path(wh.endpoint_id), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit", class: DROPDOWN_ITEM) do
                render UI::Icon.new(:refresh, class: ICON_SM)
                plain "Send test"
              end
            end
          end
        end

        signing_secret_info
      end
    end

    def signing_secret_info
      div(style: "background:#f9fafb;border:1px solid #{BORDER};border-radius:14px;padding:20px 24px;margin-top:20px") do
        p(style: "#{TYPE_BODY_MD};margin-bottom:6px") { "Webhook signature verification" }
        p(style: TYPE_CAPTION) do
          "Every webhook payload is signed with your webhook secret using HMAC-SHA256. " \
          "Always verify the X-Yagye-Signature header before processing events."
        end
        a(href: "#", style: "#{TYPE_CAPTION};color:#{BRAND};text-decoration:none;margin-top:8px;display:inline-flex;align-items:center;gap:4px") do
          "View verification guide"
          span(style: "display:flex;width:12px;height:12px") do
            render UI::Icon.new(:external_link, class: "w-full h-full")
          end
        end
      end
    end

    # ── Event logs panel ──────────────────────────────────────────────────────

    def logs_panel
      pagy       = @pagy
      deliveries = @deliveries

      render UI::Datatable.new(records: deliveries, pagy: pagy,
                               empty_message: "No delivery attempts yet. Webhook deliveries appear here once endpoints are active.") do |t|
        t.header do
          div do
            p(style: TYPE_TITLE) { "Delivery log" }
            p(style: "#{TYPE_CAPTION};margin-top:2px") { "Last 30 days. Click a row to inspect the request and response." }
          end
        end

        t.column("Event")    do |d|
          div do
            p(style: TYPE_BODY_MD) { d.event_type }
            p(style: TYPE_CAPTION) { d.short_event_id }
          end
        end
        t.column("Endpoint") { |d| code(style: "#{TYPE_MONO};font-size:11px") { d.portal_webhook_endpoint&.url || "—" } }
        t.column("Status")   { |d| render UI::StatusBadge.new(status: d.state) }
        t.column("HTTP")     { |d| http_status_chip(d) }
        t.column("Duration") { |d| span(style: TYPE_CAPTION) { d.formatted_duration } }
        t.column("Attempt")  { |d| span(style: TYPE_CAPTION) { d.attempt.to_s } }
        t.column("Sent")     { |d| span(style: TYPE_CAPTION) { d.last_applied_at.strftime("%d %b, %H:%M") } }

        t.actions do |d|
          a(href: developers_delivery_path(d.delivery_id),
            class: DROPDOWN_ITEM,
            data: { turbo_frame: "drawer-frame" }) do
            render UI::Icon.new(:eye, class: ICON_SM)
            "Inspect"
          end
          a(href: developers_delivery_path(d.delivery_id),
            class: DROPDOWN_ITEM) do
            render UI::Icon.new(:refresh, class: ICON_SM)
            "Retry"
          end
        end
      end
    end

    # ── Dialogs ───────────────────────────────────────────────────────────────

    ALL_EVENTS = %w[
      payment.paid payment.failed payment.refunded
      dispute.opened dispute.resolved
      merchant.kyb.approved merchant.kyb.rejected
    ].freeze

    def generate_key_dialog(live_mode)
      dialog(id: "generate-key-dialog",
             style: "border:none;border-radius:16px;padding:0;box-shadow:0 20px 60px rgba(0,0,0,0.18);" \
                    "width:100%;max-width:420px;background:#fff") do
        div(style: "padding:22px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Generate API key" }
          p(style: "#{TYPE_CAPTION};margin-top:3px") { "Keys are shown once. Store it immediately after creation." }
        end
        form(action: developers_keys_path, method: "post",
             style: "padding:22px 24px;display:flex;flex-direction:column;gap:14px") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "mode",               value: live_mode ? "live" : "test")
          dev_field("Key label", "label", placeholder: "e.g. Production server", required: true)
          div(style: "display:flex;gap:10px;justify-content:flex-end;margin-top:4px") do
            button(type: "button",
                   onclick: "document.getElementById('generate-key-dialog').close()",
                   class: BTN_SECONDARY) { "Cancel" }
            button(type: "submit", class: BTN_PRIMARY) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Generate"
            end
          end
        end
      end
    end

    def add_webhook_dialog
      dialog(id: "add-webhook-dialog",
             style: "border:none;border-radius:16px;padding:0;box-shadow:0 20px 60px rgba(0,0,0,0.18);" \
                    "width:100%;max-width:500px;background:#fff") do
        div(style: "padding:22px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Add webhook endpoint" }
          p(style: "#{TYPE_CAPTION};margin-top:3px") { "Yagye will POST signed events to this URL." }
        end
        form(action: developers_webhooks_path, method: "post",
             style: "padding:22px 24px;display:flex;flex-direction:column;gap:14px") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          dev_field("Endpoint URL", "url", type: "url", placeholder: "https://your-server.com/webhooks", required: true)
          div do
            p(style: "#{TYPE_MICRO};margin-bottom:8px") { "Events to receive" }
            div(style: "display:flex;flex-direction:column;gap:6px") do
              ALL_EVENTS.each do |event|
                label(style: "display:flex;align-items:center;gap:8px;cursor:pointer") do
                  input(type: "checkbox", name: "subscribed_events[]", value: event, checked: true,
                        style: "width:14px;height:14px;accent-color:#{BRAND};cursor:pointer")
                  span(style: "#{TYPE_MONO};font-size:11.5px") { event }
                end
              end
            end
          end
          div(style: "display:flex;gap:10px;justify-content:flex-end;margin-top:4px") do
            button(type: "button",
                   onclick: "document.getElementById('add-webhook-dialog').close()",
                   class: BTN_SECONDARY) { "Cancel" }
            button(type: "submit", class: BTN_PRIMARY) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add endpoint"
            end
          end
        end
      end
    end

    def dev_field(label, name, type: "text", placeholder: "", required: false)
      div do
        p(style: "#{TYPE_MICRO};margin-bottom:6px") { label }
        input(type: type, name: name, placeholder: placeholder, required: required,
              style: "width:100%;border:1px solid #{BORDER_MED};border-radius:10px;" \
                     "padding:9px 12px;font-size:13px;color:#{INK};background:#fff;" \
                     "outline:none;box-sizing:border-box",
              class: "placeholder:text-gray-400")
      end
    end

    def http_status_chip(delivery)
      code = delivery.response_status
      return span(style: TYPE_CAPTION) { "—" } unless code

      color = code.between?(200, 299) ? "#16a34a" : "#dc2626"
      bg    = code.between?(200, 299) ? "#f0fdf4" : "#fef2f2"

      span(style: "font-size:11.5px;font-weight:600;color:#{color};background:#{bg};" \
                  "padding:2px 8px;border-radius:16px;font-family:ui-monospace,monospace") do
        code.to_s
      end
    end
  end
end
