# frozen_string_literal: true

module Developers
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "api_keys", label: "API Keys" },
      { key: "webhooks", label: "Webhooks" },
      { key: "logs",     label: "Event Logs" }
    ].freeze

    ALL_EVENTS = %w[
      payment.paid payment.failed payment.refunded
      dispute.opened dispute.resolved
      merchant.kyb.approved merchant.kyb.rejected
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

    # ── API Keys panel ────────────────────────────────────────────────────────

    def api_keys_panel
      live = Current.mode == "live"

      div do
        div(class: "flex items-center justify-end mb-5") do
          render UI::Button.new(variant: :primary,
                 data: { action: "click->dialog#open", dialog_target_param: "generate-key-dialog" }) do
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
              p(class: TYPE_TITLE) { plain "#{live ? 'Live' : 'Test'} API keys" }
              p(class: "#{TYPE_CAPTION} mt-0.5") { plain "Keys are shown once at creation. Store them securely." }
            end
          end

          t.column("Name")       { |k| span(class: TYPE_BODY_MD) { plain(k.label.presence || k.kind.capitalize) } }
          t.column("Key prefix") { |k| key_prefix_cell(k) }
          t.column("Created")    { |k| span(class: TYPE_CAPTION) { plain k.created_at.strftime("%d %b %Y") } }
          t.column("Last used")  { |k| span(class: TYPE_CAPTION) { plain(k.last_used_at&.strftime("%d %b %Y") || "Never") } }
          t.column("Status")     { |k| render UI::StatusBadge.new(status: k.active ? "active" : "revoked") }

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

        quick_start_card(live) unless @api_keys.empty?
      end
    end

    def key_prefix_cell(key)
      prefix = key.key_prefix + "..."
      div(class: "flex items-center gap-2") do
        code(class: TYPE_MONO) { plain prefix }
        button(type: "button",
               title: "Copy key prefix",
               class: "flex w-6 h-6 rounded-md items-center justify-center text-gray-300 " \
                      "hover:text-gray-600 hover:bg-gray-100 transition-colors border-0 bg-transparent cursor-pointer",
               onclick: "navigator.clipboard.writeText(this.dataset.val);" \
                        "this.classList.add('!text-green-600');" \
                        "setTimeout(()=>this.classList.remove('!text-green-600'),1200)",
               data: { val: prefix }) do
          span(class: "flex w-3 h-3") do
            render UI::Icon.new(:copy, class: "w-full h-full")
          end
        end
      end
    end

    def quick_start_card(live)
      env_prefix = live ? "sk_live" : "sk_test"
      first_key  = @api_keys.select(&:active?).first
      display_key = first_key ? "#{first_key.key_prefix}..." : "#{env_prefix}_YOUR_SECRET_KEY"

      snippet = <<~CURL.strip
        curl -X POST https://api.yagye.com/v1/payments \\
          -H "Authorization: Bearer #{display_key}" \\
          -H "Content-Type: application/json" \\
          -d '{
            "amount": 10000,
            "currency": "GHS",
            "method": "mobile_money",
            "msisdn": "0241234567",
            "reference": "order_abc123"
          }'
      CURL

      div(class: "mt-5 bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "flex items-center justify-between px-6 py-5 border-b border-gray-100") do
          div do
            p(class: TYPE_TITLE) { plain "Quick start" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Test your key with a cURL request. "
              span(class: "text-amber-600 font-medium") { plain "Replace the key before going live." } unless first_key
            end
          end
          button(type: "button",
                 class: "flex items-center gap-[6px] text-[12px] font-medium text-gray-500 " \
                        "hover:text-gray-800 transition-colors border border-gray-200 rounded-lg " \
                        "px-[10px] py-[5px] bg-white cursor-pointer",
                 onclick: "navigator.clipboard.writeText(this.dataset.val);" \
                          "this.querySelector('span').textContent='Copied!';" \
                          "setTimeout(()=>this.querySelector('span').textContent='Copy snippet',1500)",
                 data: { val: snippet }) do
            render UI::Icon.new(:copy, class: "w-[12px] h-[12px]")
            span { plain "Copy snippet" }
          end
        end
        div(class: "bg-[#0d1117] rounded-b-2xl px-6 py-5 overflow-x-auto") do
          pre(class: "text-[12.5px] leading-[1.7] font-mono m-0 whitespace-pre") do
            span(class: "text-[#79c0ff]") { plain "curl" }
            span(class: "text-[#ff7b72]") { plain " -X POST" }
            plain " "
            span(class: "text-[#a5d6ff]") { plain "https://api.yagye.com/v1/payments" }
            plain " \\\n"
            span(class: "text-[#ff7b72]") { plain "  -H" }
            plain " \""
            span(class: "text-[#ffa657]") { plain "Authorization" }
            plain ": Bearer "
            span(class: first_key ? "text-[#7ee787]" : "text-[#f2cc60]") { plain display_key }
            plain "\" \\\n"
            span(class: "text-[#ff7b72]") { plain "  -H" }
            plain " \""
            span(class: "text-[#ffa657]") { plain "Content-Type" }
            plain ": application/json\" \\\n"
            span(class: "text-[#ff7b72]") { plain "  -d" }
            plain " '{\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "amount" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "10000" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "currency" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "GHS" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "method" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "mobile_money" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "msisdn" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "0241234567" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "reference" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "order_abc123" }
            plain "\"\n"
            plain "  }'"
          end
        end
      end
    end

    def test_mode_notice
      div(class: "bg-amber-50 border border-amber-200 rounded-xl px-[18px] py-[14px] mb-4 flex gap-[10px] items-start") do
        span(class: "flex w-4 h-4 text-amber-500 flex-shrink-0 mt-px") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        div do
          p(class: "text-[13px] font-semibold text-amber-900 mb-0.5") { plain "Test mode" }
          p(class: "#{TYPE_CAPTION} text-amber-700") do
            plain "Test keys are for development only. No real money moves. " \
                  "Switch to Live mode using the toggle in the sidebar to access live keys."
          end
        end
      end
    end

    # ── Webhooks panel ────────────────────────────────────────────────────────

    def webhooks_panel
      div do
        div(class: "flex items-center justify-between mb-5") do
          div do
            p(class: TYPE_BODY_MD) { plain "Webhook endpoints" }
            p(class: TYPE_CAPTION) { plain "Yagye sends signed POST requests to your endpoints for each event." }
          end
          render UI::Button.new(variant: :primary,
                 data: { action: "click->dialog#open", dialog_target_param: "add-webhook-dialog" }) do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "Add Endpoint"
          end
          add_webhook_dialog
        end

        render UI::Datatable.new(records: @webhooks,
                                 empty_message: "No webhook endpoints. Add one to receive real-time payment events.") do |t|
          t.header do
            p(class: TYPE_TITLE) { plain "Endpoints" }
          end

          t.column("URL")     { |wh| code(class: TYPE_MONO) { plain wh.url } }
          t.column("Events")  { |wh| span(class: TYPE_CAPTION) { plain "#{Array(wh.subscribed_events).size} events" } }
          t.column("Status")  { |wh| render UI::StatusBadge.new(status: wh.active ? "active" : "suspended") }
          t.column("Created") { |wh| span(class: TYPE_CAPTION) { plain wh.created_at.strftime("%d %b %Y") } }

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
      div(class: "bg-gray-50 border border-gray-100 rounded-[14px] px-6 py-5 mt-5") do
        p(class: "#{TYPE_BODY_MD} mb-1.5") { plain "Webhook signature verification" }
        p(class: TYPE_CAPTION) do
          plain "Every webhook payload is signed with your webhook secret using HMAC-SHA256. " \
                "Always verify the X-Yagye-Signature header before processing events."
        end
        a(href: "#", class: "#{TYPE_CAPTION} text-[#3D47F5] no-underline mt-2 inline-flex items-center gap-1") do
          plain "View verification guide"
          span(class: "flex w-3 h-3") do
            render UI::Icon.new(:external_link, class: "w-full h-full")
          end
        end
      end
    end

    # ── Event logs panel ──────────────────────────────────────────────────────

    def logs_panel
      render UI::Datatable.new(records: @deliveries, pagy: @pagy,
                               empty_message: "No delivery attempts yet. Webhook deliveries appear here once endpoints are active.") do |t|
        t.header do
          div do
            p(class: TYPE_TITLE) { plain "Delivery log" }
            p(class: "#{TYPE_CAPTION} mt-0.5") { plain "Last 30 days. Click a row to inspect the request and response." }
          end
        end

        t.column("Event") do |d|
          div do
            p(class: TYPE_BODY_MD) { plain d.event_type }
            p(class: TYPE_CAPTION) { plain d.short_event_id }
          end
        end
        t.column("Endpoint") { |d| code(class: "#{TYPE_MONO} text-[11px]") { plain(d.portal_webhook_endpoint&.url || "—") } }
        t.column("Status")   { |d| render UI::StatusBadge.new(status: d.state) }
        t.column("HTTP")     { |d| http_status_chip(d) }
        t.column("Duration") { |d| span(class: TYPE_CAPTION) { plain d.formatted_duration } }
        t.column("Attempt")  { |d| span(class: TYPE_CAPTION) { plain d.attempt.to_s } }
        t.column("Sent")     { |d| span(class: TYPE_CAPTION) { plain d.last_applied_at.strftime("%d %b, %H:%M") } }

        t.actions do |d|
          a(href: developers_delivery_path(d),
            class: DROPDOWN_ITEM,
            data: { turbo_frame: "drawer-frame" }) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "Inspect"
          end
          a(href: developers_delivery_path(d), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:refresh, class: ICON_SM)
            plain "Retry"
          end
        end
      end
    end

    # ── Dialogs ───────────────────────────────────────────────────────────────

    def generate_key_dialog(live_mode)
      dialog(id: "generate-key-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[420px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Generate API key" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Keys are shown once. Store it immediately after creation." }
        end
        form(action: developers_keys_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "mode",               value: live_mode ? "live" : "test")
          render UI::InputField.new(name: "label", label: "Key label", placeholder: "e.g. Production server", required: true)
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "generate-key-dialog" }) { plain "Cancel" }
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Generate"
            end
          end
        end
      end
    end

    def add_webhook_dialog
      dialog(id: "add-webhook-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[500px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Add webhook endpoint" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Yagye will POST signed events to this URL." }
        end
        form(action: developers_webhooks_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "url", label: "Endpoint URL", type: "url",
                                    placeholder: "https://your-server.com/webhooks", required: true)
          div do
            p(class: "#{TYPE_MICRO} mb-2") { plain "Events to receive" }
            div(class: "flex flex-col gap-1.5") do
              ALL_EVENTS.each do |event|
                label(class: "flex items-center gap-2 cursor-pointer") do
                  input(type: "checkbox", name: "subscribed_events[]", value: event, checked: true,
                        class: "w-[14px] h-[14px] cursor-pointer",
                        style: "accent-color:#{BRAND}")
                  span(class: TYPE_MONO) { plain event }
                end
              end
            end
          end
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "add-webhook-dialog" }) { plain "Cancel" }
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add endpoint"
            end
          end
        end
      end
    end

    def http_status_chip(delivery)
      status_code = delivery.response_status
      return span(class: TYPE_CAPTION) { plain "—" } unless status_code

      color = status_code.between?(200, 299) ? "#16a34a" : "#dc2626"
      bg    = status_code.between?(200, 299) ? "#f0fdf4" : "#fef2f2"

      span(class: "text-[11.5px] font-semibold px-2 py-[2px] rounded-full font-mono",
           style: "color:#{color};background:#{bg}") { plain status_code.to_s }
    end
  end
end
