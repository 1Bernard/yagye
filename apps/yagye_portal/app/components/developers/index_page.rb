# frozen_string_literal: true

module Developers
  class IndexPage < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "api_keys",  label: "API Keys" },
      { key: "webhooks",  label: "Webhooks" },
      { key: "logs",      label: "Event Logs" }
    ].freeze

    def initialize(tab: "api_keys", api_keys: [], webhooks: [])
      @tab      = tab
      @api_keys = api_keys
      @webhooks = webhooks
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :developers,
        title:      "Developers",
        breadcrumbs: [ { label: "Developers" } ]
      ) do
        page_header
        tab_bar
        case @tab
        when "api_keys" then api_keys_panel
        when "webhooks" then webhooks_panel
        when "logs"     then logs_panel
        end
      end
    end

    private

    def page_header
      div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:24px") do
        div do
          p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Account" }
          h1(style: TYPE_DISPLAY) { "Developer Tools" }
        end
      end
    end

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
                 style: "cursor:not-allowed;opacity:0.6", disabled: true) do
            render UI::Icon.new(:plus, class: ICON_SM)
            "Generate Key"
          end
        end

        test_mode_notice unless live

        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:20px;overflow:hidden") do
          div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
            div(style: "display:flex;align-items:center;justify-content:space-between") do
              p(style: TYPE_TITLE) { "#{live ? 'Live' : 'Test'} API keys" }
              p(style: TYPE_CAPTION) { "Keys are shown once at creation. Store them securely." }
            end
          end

          if @api_keys.empty?
            empty_keys_state
          else
            keys_table
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

    def empty_keys_state
      div(style: "padding:56px 24px;text-align:center") do
        div(style: "width:48px;height:48px;border-radius:16px;background:#f3f4f6;" \
                   "display:flex;align-items:center;justify-content:center;margin:0 auto 16px") do
          span(style: "display:flex;width:22px;height:22px;color:#{SUBTLE_TEXT}") do
            render UI::Icon.new(:key, class: "w-full h-full")
          end
        end
        p(style: "#{TYPE_BODY_MD};margin-bottom:6px") { "No API keys yet" }
        p(style: "#{TYPE_CAPTION};margin-bottom:20px") do
          "Generate your first #{Current.mode == 'live' ? 'live' : 'test'} key to start integrating with Yagye."
        end
        button(type: "button", class: BTN_PRIMARY, style: "cursor:not-allowed;opacity:0.6", disabled: true) do
          render UI::Icon.new(:plus, class: ICON_SM)
          "Generate Key"
        end
      end
    end

    def keys_table
      table(style: "width:100%;border-collapse:collapse") do
        thead do
          tr do
            %w[Name Key\ prefix Created Last\ used Status Actions].each do |h|
              th(style: "#{TABLE_TH}") { h }
            end
          end
        end
        tbody do
          @api_keys.each do |key|
            tr(style: "border-top:1px solid #{BORDER}") do
              td(style: TABLE_CELL) { span(style: TYPE_BODY_MD) { key.label.presence || key.kind.capitalize } }
              td(style: TABLE_CELL) { code(style: TYPE_MONO) { key.key_prefix + "..." } }
              td(style: TABLE_CELL) { span(style: TYPE_CAPTION) { key.created_at.strftime("%d %b %Y") } }
              td(style: TABLE_CELL) { span(style: TYPE_CAPTION) { key.last_used_at&.strftime("%d %b %Y") || "Never" } }
              td(style: TABLE_CELL) { render UI::StatusBadge.new(status: key.active ? "active" : "revoked") }
              td(style: TABLE_CELL) do
                button(type: "button", class: DROPDOWN_ITEM) do
                  render UI::Icon.new(:x, class: ICON_SM)
                  "Revoke"
                end
              end
            end
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
          button(type: "button", class: BTN_PRIMARY, style: "cursor:not-allowed;opacity:0.6", disabled: true) do
            render UI::Icon.new(:plus, class: ICON_SM)
            "Add Endpoint"
          end
        end

        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:20px;overflow:hidden") do
          if @webhooks.empty?
            empty_webhooks_state
          else
            webhooks_table
          end
        end

        signing_secret_info
      end
    end

    def empty_webhooks_state
      div(style: "padding:56px 24px;text-align:center") do
        div(style: "width:48px;height:48px;border-radius:16px;background:#f3f4f6;" \
                   "display:flex;align-items:center;justify-content:center;margin:0 auto 16px") do
          span(style: "display:flex;width:22px;height:22px;color:#{SUBTLE_TEXT}") do
            render UI::Icon.new(:globe, class: "w-full h-full")
          end
        end
        p(style: "#{TYPE_BODY_MD};margin-bottom:6px") { "No webhook endpoints" }
        p(style: TYPE_CAPTION) { "Add an endpoint to receive real-time payment events." }
      end
    end

    def webhooks_table
      table(style: "width:100%;border-collapse:collapse") do
        thead do
          tr do
            %w[Endpoint\ URL Events Status Created Actions].each do |h|
              th(style: "#{TABLE_TH}") { h }
            end
          end
        end
        tbody do
          @webhooks.each do |wh|
            tr(style: "border-top:1px solid #{BORDER}") do
              td(style: TABLE_CELL) { code(style: TYPE_MONO) { wh.url } }
              td(style: TABLE_CELL) { span(style: TYPE_CAPTION) { "#{Array(wh.subscribed_events).size} events" } }
              td(style: TABLE_CELL) { render UI::StatusBadge.new(status: wh.active ? "active" : "suspended") }
              td(style: TABLE_CELL) { span(style: TYPE_CAPTION) { wh.created_at.strftime("%d %b %Y") } }
              td(style: TABLE_CELL) do
                a(href: "#", class: DROPDOWN_ITEM) do
                  render UI::Icon.new(:edit, class: ICON_SM)
                  "Edit"
                end
              end
            end
          end
        end
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
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:20px;padding:56px 24px;text-align:center") do
        div(style: "width:48px;height:48px;border-radius:16px;background:#f3f4f6;" \
                   "display:flex;align-items:center;justify-content:middle;margin:0 auto 16px") do
          span(style: "display:flex;width:22px;height:22px;color:#{SUBTLE_TEXT}") do
            render UI::Icon.new(:layers, class: "w-full h-full")
          end
        end
        p(style: "#{TYPE_BODY_MD};margin-bottom:6px") { "Event logs" }
        p(style: TYPE_CAPTION) { "Webhook delivery history will be available in a future release." }
      end
    end
  end
end
