# frozen_string_literal: true

module Developers
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "quickstart", label: "Quickstart" },
      { key: "api_keys",   label: "API Keys" },
      { key: "webhooks",   label: "Webhooks" },
      { key: "logs",       label: "Event Logs" },
      { key: "reference",  label: "API Reference" }
    ].freeze

    METHOD_BADGE = {
      "get"    => { bg: "#f0fdf4", color: "#16a34a", text: "GET" },
      "post"   => { bg: "rgba(61,71,245,0.08)", color: "#3D47F5", text: "POST" },
      "delete" => { bg: "#fef2f2", color: "#dc2626", text: "DEL" },
      "patch"  => { bg: "#fffbeb", color: "#d97706", text: "PATCH" },
      "put"    => { bg: "#fffbeb", color: "#d97706", text: "PUT" }
    }.freeze

    TAG_ICON = {
      "Checkout Sessions" => :credit_card,
      "Payments"          => :wallet,
      "Payment Links"     => :link,
      "Invoices"          => :file,
      "Refunds"           => :refresh,
      "Disputes"          => :alert_circle,
      "Customers"         => :users,
      "Merchants"         => :building,
      "Settlements"       => :bank,
      "Payouts"           => :trending_up,
      "API Keys"          => :key,
      "Compliance / KYB"  => :shield
    }.freeze

    ALL_EVENTS = %w[
      payment.paid payment.failed payment.refunded
      dispute.opened dispute.resolved
      merchant.kyb.approved merchant.kyb.rejected
    ].freeze

    def initialize(tab: "api_keys", api_keys: [], webhooks: [], deliveries: nil, pagy: nil, reveal_key: nil, reveal_webhook_secret: nil, openapi_spec: {}, sandbox_enabled: false)
      @tab          = tab
      @api_keys     = api_keys
      @webhooks     = webhooks
      @deliveries   = deliveries || []
      @pagy         = pagy
      @reveal_key            = reveal_key
      @reveal_webhook_secret = reveal_webhook_secret
      @openapi_spec          = openapi_spec || {}
      @sandbox_enabled       = sandbox_enabled
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :developers,
        title:      "Developers",
        breadcrumbs: [ { label: "Developers" } ]
      ) do
        reveal_webhook_secret_banner if @reveal_webhook_secret
        tab_bar
        case @tab
        when "quickstart" then quickstart_panel
        when "api_keys"   then api_keys_panel
        when "webhooks"   then webhooks_panel
        when "logs"       then logs_panel
        when "reference"  then reference_panel
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
        reveal_key_banner if @reveal_key

        render UI::Datatable.new(records: @api_keys,
                                 empty_message: "No API keys yet. Generate your first key to start integrating.") do |t|
          t.header do
            div(class: "flex items-center justify-between w-full") do
              div do
                div(class: "flex items-center gap-2 mb-[3px]") do
                  p(class: TYPE_TITLE) { plain "#{live ? 'Live' : 'Test'} API keys" }
                  unless live
                    if sandbox_enabled?
                      span(class: "#{BADGE} #{STATUS_INFO}") { plain "PSP Sandbox" }
                    else
                      span(class: "#{BADGE} #{STATUS_NEUTRAL}") { plain "Simulation" }
                    end
                  end
                end
                p(class: "#{TYPE_CAPTION} mt-0.5") do
                  plain "Full keys are shown "
                  span(class: "font-semibold text-gray-600") { plain "once" }
                  plain " at creation and never again. Only the prefix is stored."
                end
              end
              render UI::Button.new(variant: :primary, href: new_developers_key_path,
                                    data: { turbo_frame: "drawer-frame" }) do
                render UI::Icon.new(:plus, class: ICON_SM)
                plain "Generate Key"
              end
            end
          end

          t.column("Name") do |k|
            div do
              span(class: TYPE_BODY_MD) { plain(k.label.presence || k.kind.capitalize) }
              span(class: "ml-1.5 text-[10px] font-semibold px-[5px] py-[1px] rounded-full " \
                         "#{k.kind == 'secret' ? 'bg-amber-50 text-amber-700' : 'bg-gray-100 text-gray-500'}") do
                plain k.kind == "secret" ? "secret" : "public"
              end
            end
          end
          t.column("Key") do |k|
            div(class: "flex items-center gap-2") do
              code(class: TYPE_MONO) { plain "#{k.key_prefix}..." }
              button(type: "button",
                     title: "Copy prefix — useful for grepping API logs",
                     class: "flex items-center gap-[3px] px-[5px] h-[22px] rounded-md text-gray-400 " \
                            "hover:text-gray-700 hover:bg-gray-100 transition-colors border-0 bg-transparent cursor-pointer",
                     data: { controller: "clipboard", clipboard_text_value: k.key_prefix,
                             action: "click->clipboard#copy" }) do
                span(class: "flex w-[11px] h-[11px] flex-shrink-0") { render UI::Icon.new(:copy, class: "w-full h-full") }
                span(class: "text-[10px] font-medium text-green-600",
                     data: { clipboard_target: "label" }) { }
              end
            end
          end
          t.column("Created")    { |k| span(class: TYPE_CAPTION) { plain fmt_date(k.created_at) } }
          t.column("Last used")  { |k| span(class: TYPE_CAPTION) { plain(k.last_used_at ? fmt_date(k.last_used_at) : "Never") } }
          t.column("Status")     { |k| render UI::StatusBadge.new(status: k.active ? "active" : "revoked") }

          t.actions do |k|
            if k.active?
              a(href: revoke_modal_developers_key_path(k.key_id),
                class: DROPDOWN_ITEM_DANGER,
                data: { turbo_frame: "modal-frame" }) do
                render UI::Icon.new(:x, class: ICON_SM)
                plain "Revoke"
              end
            end
          end
        end

        div(class: "mt-3 flex items-start gap-2 px-1") do
          span(class: "flex w-[13px] h-[13px] text-amber-500 flex-shrink-0 mt-[1px]") do
            render UI::Icon.new(:info_circle, class: "w-full h-full")
          end
          p(class: "text-[11.5px] text-gray-500 leading-[1.5]") do
            plain "The table shows only the key prefix — the full key is only visible immediately after creation. "
            plain "If you didn't copy it, revoke the key using the ⋯ menu and generate a new one."
          end
        end

        quick_start_card(live) unless @api_keys.empty?
      end
    end

    def quick_start_card(live)
      env_prefix  = live ? "ysk_live" : "ysk_test"
      first_key   = @api_keys.select { |k| k.active? && k.kind == "secret" }.first ||
                    @api_keys.select(&:active?).first
      display_key = first_key ? "#{first_key.key_prefix}..." : "#{env_prefix}_YOUR_SECRET_KEY"

      snippet = <<~CURL.strip
        curl -X POST https://api.yagye.com/v1/checkout-sessions \\
          -H "Authorization: Bearer #{display_key}" \\
          -H "Content-Type: application/json" \\
          -d '{
            "currency": "GHS",
            "subtotal_amount": 10000,
            "total_amount": 10000,
            "description": "Order #123",
            "success_url": "https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}",
            "cancel_url": "https://yourstore.com/cart"
          }'
      CURL

      div(class: "mt-5 #{SURFACE_CARD} overflow-hidden") do
        div(class: "flex items-center justify-between px-6 py-5 border-b border-gray-100") do
          div do
            p(class: TYPE_TITLE) { plain "Quick start" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Create a checkout session and redirect your customer. "
              span(class: "text-amber-600 font-medium") { plain "Replace the key before going live." } unless first_key
            end
          end
          button(type: "button",
                 class: "flex items-center gap-[6px] text-[12px] font-medium text-gray-500 " \
                        "hover:text-gray-800 transition-colors border border-gray-200 rounded-lg " \
                        "px-[10px] py-[5px] bg-white cursor-pointer",
                 data: { controller: "clipboard", clipboard_text_value: snippet,
                         action: "click->clipboard#copy" }) do
            render UI::Icon.new(:copy, class: "w-[12px] h-[12px]")
            span(data: { clipboard_target: "label" }) { plain "Copy snippet" }
          end
        end
        div(class: "bg-[#0d1117] rounded-b-2xl px-6 py-5 overflow-x-auto") do
          pre(class: "text-[12.5px] leading-[1.7] font-mono m-0 whitespace-pre text-[#c9d1d9]") do
            span(class: "text-[#79c0ff]") { plain "curl" }
            span(class: "text-[#ff7b72]") { plain " -X POST" }
            plain " "
            span(class: "text-[#a5d6ff]") { plain "https://api.yagye.com/v1/checkout-sessions" }
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
            span(class: "text-[#79c0ff]") { plain "currency" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "GHS" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "subtotal_amount" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "10000" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "total_amount" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "10000" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "description" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "Order #123" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "success_url" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "cancel_url" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "https://yourstore.com/cart" }
            plain "\"\n"
            plain "  }'"
          end
        end
      end
    end

    # ── Quickstart panel ──────────────────────────────────────────────────────

    def quickstart_panel
      env_prefix  = Current.mode == "live" ? "ysk_live" : "ysk_test"
      first_key   = @api_keys.select { |k| k.active? && k.kind == "secret" }.first ||
                    @api_keys.select(&:active?).first
      display_key = first_key ? "#{first_key.key_prefix}..." : "#{env_prefix}_YOUR_SECRET_KEY"
      key_color   = first_key ? "text-[#7ee787]" : "text-[#f2cc60]"

      div(class: "flex flex-col gap-5") do
        test_mode_notice unless Current.mode == "live"

        # Header callout
        div(class: "#{SURFACE_CARD} px-6 py-5") do
          div(class: "flex items-start gap-4") do
            div(class: "w-10 h-10 rounded-xl icon-brand flex items-center justify-center flex-shrink-0") do
              span(class: "flex w-[18px] h-[18px]") { render UI::Icon.new(:external_link, class: "w-full h-full") }
            end
            div do
              p(class: "text-[14px] font-semibold text-gray-900 mb-1") { plain "Integrate the Yagye hosted checkout" }
              p(class: TYPE_CAPTION) do
                plain "Four steps to accept payments in your app. No card UI to build — your customer pays on the " \
                      "Yagye-hosted checkout page. All amounts are in the smallest currency unit (pesewas for GHS)."
              end
            end
          end
        end

        # Step 1
        qs_step("1", "Get a test API key", :key, "icon-green") do
          p(class: TYPE_CAPTION) do
            plain "Go to "
            a(href: developers_path(tab: "api_keys"), class: "text-[#3D47F5] font-medium no-underline") { plain "API Keys" }
            plain " and generate a key. Copy it immediately — the full key is only shown once at creation. Only the prefix is stored after that."
          end
          unless first_key
            div(class: "mt-3") do
              render UI::Button.new(variant: :primary, href: new_developers_key_path,
                                    data: { turbo_frame: "drawer-frame" }) do
                render UI::Icon.new(:plus, class: ICON_SM)
                plain "Generate test key"
              end
            end
          end
        end

        # Step 2 — create checkout session
        session_snippet = <<~CURL.strip
          curl -X POST https://api.yagye.com/v1/checkout-sessions \\
            -H "Authorization: Bearer #{display_key}" \\
            -H "Content-Type: application/json" \\
            -H "Idempotency-Key: $(uuidgen)" \\
            -d '{
              "currency": "GHS",
              "subtotal_amount": 25000,
              "total_amount": 25000,
              "description": "Order #001",
              "success_url": "https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}",
              "cancel_url":  "https://yourstore.com/cart",
              "collect_email": true,
              "line_items": [
                {
                  "kind": "item",
                  "description": "Blue Sneakers – Size 42",
                  "quantity": 1,
                  "unit_amount": 25000,
                  "total_amount": 25000
                }
              ],
              "metadata": { "order_id": "ord_789" }
            }'
        CURL

        node_session_snippet = <<~JS.strip
          // Node.js (native fetch, Node 18+)
          const response = await fetch('https://api.yagye.com/v1/checkout-sessions', {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${apiKey}`,
              'Content-Type': 'application/json',
              'Idempotency-Key': crypto.randomUUID(),
            },
            body: JSON.stringify({
              currency: 'GHS',
              subtotal_amount: 25000,
              total_amount: 25000,
              description: 'Order #001',
              success_url: 'https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}',
              cancel_url: 'https://yourstore.com/cart',
              collect_email: true,
              line_items: [{
                kind: 'item',
                description: 'Blue Sneakers – Size 42',
                quantity: 1,
                unit_amount: 25000,
                total_amount: 25000,
              }],
              metadata: { order_id: 'ord_789' },
            }),
          });
          const session = await response.json();
          // Redirect your customer to the hosted checkout page
          window.location.href = session.checkout_url;
        JS

        python_session_snippet = <<~PY.strip
          # Python (httpx; install: pip install httpx)
          import httpx, uuid

          r = httpx.post(
              "https://api.yagye.com/v1/checkout-sessions",
              headers={
                  "Authorization": f"Bearer {api_key}",
                  "Idempotency-Key": str(uuid.uuid4()),
              },
              json={
                  "currency": "GHS",
                  "subtotal_amount": 25000,
                  "total_amount": 25000,
                  "description": "Order #001",
                  "success_url": "https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}",
                  "cancel_url": "https://yourstore.com/cart",
                  "collect_email": True,
                  "line_items": [{
                      "kind": "item",
                      "description": "Blue Sneakers – Size 42",
                      "quantity": 1,
                      "unit_amount": 25000,
                      "total_amount": 25000,
                  }],
                  "metadata": {"order_id": "ord_789"},
              },
          )
          session = r.json()
          # Redirect your customer to: session["checkout_url"]
        PY

        php_session_snippet = <<~'PHP'.strip
          <?php
          // PHP (Guzzle + ramsey/uuid: composer require guzzlehttp/guzzle ramsey/uuid)
          use GuzzleHttp\Client;
          use Ramsey\Uuid\Uuid;

          $client   = new Client();
          $response = $client->post('https://api.yagye.com/v1/checkout-sessions', [
              'headers' => [
                  'Authorization'   => 'Bearer ' . $apiKey,
                  'Content-Type'    => 'application/json',
                  'Idempotency-Key' => Uuid::uuid4()->toString(),
              ],
              'json' => [
                  'currency'        => 'GHS',
                  'subtotal_amount' => 25000,
                  'total_amount'    => 25000,
                  'description'     => 'Order #001',
                  'success_url'     => 'https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}',
                  'cancel_url'      => 'https://yourstore.com/cart',
                  'collect_email'   => true,
                  'line_items'      => [[
                      'kind'         => 'item',
                      'description'  => 'Blue Sneakers – Size 42',
                      'quantity'     => 1,
                      'unit_amount'  => 25000,
                      'total_amount' => 25000,
                  ]],
                  'metadata'        => ['order_id' => 'ord_789'],
              ],
          ]);
          $session = json_decode($response->getBody(), true);
          // Redirect your customer:
          header('Location: ' . $session['checkout_url']);
        PHP

        ruby_session_snippet = <<~'RUBY'.strip
          # Ruby (stdlib only — no gems needed)
          require 'net/http'
          require 'json'
          require 'securerandom'

          uri  = URI('https://api.yagye.com/v1/checkout-sessions')
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          req = Net::HTTP::Post.new(uri)
          req['Authorization']   = "Bearer #{api_key}"
          req['Content-Type']    = 'application/json'
          req['Idempotency-Key'] = SecureRandom.uuid

          req.body = {
            currency:        'GHS',
            subtotal_amount: 25_000,
            total_amount:    25_000,
            description:     'Order #001',
            success_url:     'https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}',
            cancel_url:      'https://yourstore.com/cart',
            collect_email:   true,
            line_items:      [{
              kind:         'item',
              description:  'Blue Sneakers – Size 42',
              quantity:     1,
              unit_amount:  25_000,
              total_amount: 25_000
            }],
            metadata:        { order_id: 'ord_789' }
          }.to_json

          res     = http.request(req)
          session = JSON.parse(res.body)
          # Redirect your customer to: session['checkout_url']
        RUBY

        session_response_json = <<~JSON.strip
          {
            "id":               "cks_a1b2c3d4e5f6a7b8c9d0",
            "object":           "checkout_session",
            "status":           "open",
            "mode":             "test",
            "currency":         "GHS",
            "subtotal_amount":  25000,
            "total_amount":     25000,
            "description":      "Order #001",
            "checkout_url":     "https://pay.yagye.com/s/cks_a1b2c3d4e5f6a7b8c9d0",
            "success_url":      "https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}",
            "cancel_url":       "https://yourstore.com/cart",
            "collect_email":    true,
            "line_items": [{
              "kind":           "item",
              "description":    "Blue Sneakers – Size 42",
              "quantity":       1,
              "unit_amount":    25000,
              "total_amount":   25000
            }],
            "metadata":         { "order_id": "ord_789" },
            "created_at":       "2026-11-08T10:00:00Z",
            "expires_at":       "2026-11-08T10:30:00Z"
          }
        JSON

        qs_step("2", "Create a checkout session", :credit_card, "icon-brand") do
          p(class: TYPE_CAPTION) do
            plain "Call "
            code(class: TYPE_MONO) { plain "POST /v1/checkout-sessions" }
            plain " from your server with the items and redirect URLs. The response contains a "
            code(class: TYPE_MONO) { plain "checkout_url" }
            plain " — redirect your customer there."
          end
          lang_snippets = {
            "curl"   => session_snippet,
            "node"   => node_session_snippet,
            "python" => python_session_snippet,
            "php"    => php_session_snippet,
            "ruby"   => ruby_session_snippet
          }
          qs_multi_lang_block(lang_snippets) do
            span(class: "text-[#79c0ff]") { plain "curl" }
            span(class: "text-[#ff7b72]") { plain " -X POST" }
            plain " "
            span(class: "text-[#a5d6ff]") { plain "https://api.yagye.com/v1/checkout-sessions" }
            plain " \\\n"
            span(class: "text-[#ff7b72]") { plain "  -H" }
            plain " \""
            span(class: "text-[#ffa657]") { plain "Authorization" }
            plain ": Bearer "
            span(class: key_color) { plain display_key }
            plain "\" \\\n"
            span(class: "text-[#ff7b72]") { plain "  -H" }
            plain " \""
            span(class: "text-[#ffa657]") { plain "Content-Type" }
            plain ": application/json\" \\\n"
            span(class: "text-[#ff7b72]") { plain "  -H" }
            plain " \""
            span(class: "text-[#ffa657]") { plain "Idempotency-Key" }
            plain ": $(uuidgen)\" \\\n"
            span(class: "text-[#ff7b72]") { plain "  -d" }
            plain " '{\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "currency" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "GHS" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "subtotal_amount" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "25000" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "total_amount" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "25000" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "description" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "Order #001" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "success_url" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "cancel_url" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "https://yourstore.com/cart" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "collect_email" }
            plain "\": "
            span(class: "text-[#79c0ff]") { plain "true" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "line_items" }
            plain "\": [\n"
            plain "      {\n"
            plain "        \""
            span(class: "text-[#79c0ff]") { plain "kind" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "item" }
            plain "\",\n"
            plain "        \""
            span(class: "text-[#79c0ff]") { plain "description" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "Blue Sneakers – Size 42" }
            plain "\",\n"
            plain "        \""
            span(class: "text-[#79c0ff]") { plain "quantity" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "1" }
            plain ",\n"
            plain "        \""
            span(class: "text-[#79c0ff]") { plain "unit_amount" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "25000" }
            plain ",\n"
            plain "        \""
            span(class: "text-[#79c0ff]") { plain "total_amount" }
            plain "\": "
            span(class: "text-[#a5d6ff]") { plain "25000" }
            plain "\n"
            plain "      }\n"
            plain "    ],\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "metadata" }
            plain "\": { \""
            span(class: "text-[#79c0ff]") { plain "order_id" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "ord_789" }
            plain "\" }\n"
            plain "  }'"
          end
          qs_idempotency_note
          qs_response_viewer("Expected response — 201 Created", session_response_json)
          qs_sandbox_run_section if current_user&.merchant_user?
        end

        # Step 3 — redirect
        js_snippet = <<~JS.strip
          // After creating the session on your server:
          const { checkout_url } = await response.json();
          window.location.href = checkout_url;
        JS

        qs_step("3", "Redirect the customer", :external_link, "icon-purple") do
          p(class: TYPE_CAPTION) do
            plain "Redirect the customer to the "
            code(class: TYPE_MONO) { plain "checkout_url" }
            plain ". They pick their payment method (Mobile Money or card), enter details, and pay on Yagye's hosted page."
          end
          qs_code_block(js_snippet, display_key, key_color, "Copy redirect code", lang: :js) do
            span(class: "text-[#8b949e]") { plain "// After creating the session on your server:" }
            plain "\n"
            span(class: "text-[#ff7b72]") { plain "const" }
            plain " { "
            span(class: "text-[#79c0ff]") { plain "checkout_url" }
            plain " } = "
            span(class: "text-[#ff7b72]") { plain "await" }
            plain " response."
            span(class: "text-[#79c0ff]") { plain "json" }
            plain "();\n"
            plain "window.location."
            span(class: "text-[#ffa657]") { plain "href" }
            plain " = checkout_url;"
          end
          div(class: "mt-3 bg-gray-50 border border-gray-100 rounded-xl px-4 py-3") do
            p(class: "text-[12px] text-gray-600") do
              plain "The customer is returned to your "
              code(class: TYPE_MONO) { plain "success_url" }
              plain " (or "
              code(class: TYPE_MONO) { plain "cancel_url" }
              plain ") after checkout."
            end
          end
        end

        # Step 4 — webhook
        webhook_snippet = <<~JSON.strip
          {
            "id":         "evt_01j7x4k2-...",
            "object":     "event",
            "event":      "payment.paid",
            "created_at": "2026-09-22T10:30:00Z",
            "livemode":   false,
            "data": {
              "object": {
                "id":                  "pay_01j7x4k2-...",
                "object":              "payment",
                "status":              "paid",
                "amount":              25000,
                "net_amount":          24250,
                "currency":            "GHS",
                "method":              "mobile_money",
                "provider":            "mtn_momo",
                "merchant_reference":  "ord_789",
                "checkout_session_id": "cks_01j7x4k2-...",
                "customer_msisdn":     "0241000001",
                "paid_at":             "2026-09-22T10:30:00Z"
              }
            }
          }
        JSON

        qs_step("4", "Listen for payment.paid", :bell, "icon-teal") do
          p(class: TYPE_CAPTION) do
            plain "Register a webhook endpoint in "
            a(href: developers_path(tab: "webhooks"), class: "text-[#3D47F5] font-medium no-underline") { plain "Webhooks" }
            plain " and subscribe to "
            code(class: TYPE_MONO) { plain "payment.paid" }
            plain ". Always verify the "
            code(class: TYPE_MONO) { plain "X-Yagye-Signature" }
            plain " header (HMAC-SHA256) before fulfilling the order."
          end
          qs_code_block(webhook_snippet, display_key, key_color, "Copy event payload", lang: :json) do
            plain "{\n"
            plain "  \""
            span(class: "text-[#79c0ff]") { plain "id" }
            plain "\":         \""
            span(class: "text-[#a5d6ff]") { plain "evt_01j7x4k2-..." }
            plain "\",\n"
            plain "  \""
            span(class: "text-[#79c0ff]") { plain "object" }
            plain "\":     \""
            span(class: "text-[#a5d6ff]") { plain "event" }
            plain "\",\n"
            plain "  \""
            span(class: "text-[#79c0ff]") { plain "event" }
            plain "\":      \""
            span(class: "text-[#a5d6ff]") { plain "payment.paid" }
            plain "\",\n"
            plain "  \""
            span(class: "text-[#79c0ff]") { plain "created_at" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "2026-09-22T10:30:00Z" }
            plain "\",\n"
            plain "  \""
            span(class: "text-[#79c0ff]") { plain "livemode" }
            plain "\":   "
            span(class: "text-[#79c0ff]") { plain "false" }
            plain ",\n"
            plain "  \""
            span(class: "text-[#79c0ff]") { plain "data" }
            plain "\": { \""
            span(class: "text-[#79c0ff]") { plain "object" }
            plain "\": {\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "id" }
            plain "\":                  \""
            span(class: "text-[#a5d6ff]") { plain "pay_01j7x4k2-..." }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "status" }
            plain "\":              \""
            span(class: "text-[#a5d6ff]") { plain "paid" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "amount" }
            plain "\":              "
            span(class: "text-[#a5d6ff]") { plain "25000" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "net_amount" }
            plain "\":          "
            span(class: "text-[#a5d6ff]") { plain "24250" }
            plain ",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "currency" }
            plain "\":            \""
            span(class: "text-[#a5d6ff]") { plain "GHS" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "method" }
            plain "\":              \""
            span(class: "text-[#a5d6ff]") { plain "mobile_money" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "provider" }
            plain "\":            \""
            span(class: "text-[#a5d6ff]") { plain "mtn_momo" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "merchant_reference" }
            plain "\":  \""
            span(class: "text-[#a5d6ff]") { plain "ord_789" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "checkout_session_id" }
            plain "\": \""
            span(class: "text-[#a5d6ff]") { plain "cks_01j7x4k2-..." }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "customer_msisdn" }
            plain "\":     \""
            span(class: "text-[#a5d6ff]") { plain "0241000001" }
            plain "\",\n"
            plain "    \""
            span(class: "text-[#79c0ff]") { plain "paid_at" }
            plain "\":             \""
            span(class: "text-[#a5d6ff]") { plain "2026-09-22T10:30:00Z" }
            plain "\"\n  } }\n}"
          end
        end

        # OpenAPI reference link
        div(class: "bg-gray-50 border border-gray-100 rounded-[14px] px-6 py-5 " \
                   "flex items-center justify-between gap-4") do
          div do
            p(class: "text-[13px] font-semibold text-gray-900 mb-0.5") { plain "Full API reference" }
            p(class: TYPE_CAPTION) { plain "Every endpoint, parameter, and response schema." }
          end
          a(href: developers_path(tab: "reference"), class: BTN_SECONDARY) do
            render UI::Icon.new(:hash, class: ICON_SM)
            plain "API Reference"
          end
        end
      end
    end

    def qs_step(number, title, icon_name, color_cls, &block)
      div(class: "#{SURFACE_CARD} overflow-hidden") do
        div(class: "flex items-center gap-3 px-6 py-4 border-b border-gray-100") do
          div(class: "w-8 h-8 rounded-xl #{color_cls} flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(icon_name, class: "w-full h-full") }
          end
          div(class: "flex items-center gap-2") do
            span(class: "#{BADGE_XS} #{STATUS_INFO}") { plain "Step #{number}" }
            p(class: "text-[13.5px] font-semibold text-gray-900") { plain title }
          end
        end
        div(class: "px-6 py-5") { yield }
      end
    end

    def qs_code_block(snippet, display_key, key_color, copy_label, lang: :curl, &block)
      div(class: "mt-3 bg-[#0d1117] rounded-xl overflow-hidden") do
        div(class: "flex items-center justify-between px-4 py-2 border-b border-[#30363d]") do
          span(class: "text-[10.5px] font-mono text-[#8b949e]") { plain lang.to_s.upcase }
          button(type: "button",
                 class: "flex items-center gap-[5px] text-[11px] text-[#8b949e] " \
                        "hover:text-[#c9d1d9] transition-colors cursor-pointer bg-transparent border-0",
                 data: { controller: "clipboard", clipboard_text_value: snippet,
                         action: "click->clipboard#copy" }) do
            render UI::Icon.new(:copy, class: "w-[11px] h-[11px]")
            span(data: { clipboard_target: "label" }) { plain copy_label }
          end
        end
        div(class: "px-5 py-4 overflow-x-auto") do
          pre(class: "text-[12px] leading-[1.7] font-mono m-0 whitespace-pre text-[#c9d1d9]") do
            block ? yield : plain(snippet)
          end
        end
      end
    end

    def qs_response_field(key, value, hint)
      div(class: "bg-gray-50 border border-gray-100 rounded-xl px-4 py-3") do
        p(class: "text-[11px] font-mono font-semibold text-gray-700") { plain key }
        p(class: "text-[12px] font-mono text-[#3D47F5] mt-[2px] truncate") { plain value }
        p(class: "#{TYPE_CAPTION} mt-1") { plain hint }
      end
    end

    LANG_LABELS = {
      "curl"   => "curl",
      "node"   => "Node.js",
      "python" => "Python",
      "php"    => "PHP",
      "ruby"   => "Ruby"
    }.freeze

    # snippets = { "curl" => code_string, "node" => code_string, ... }
    # curl panel gets Phlex syntax-highlighting via block; others plain text.
    def qs_multi_lang_block(snippets, &block)
      div(class: "mt-3 bg-[#0d1117] rounded-xl overflow-hidden",
          data: { controller: "code-tabs" }) do
        div(class: "flex items-center justify-between px-4 py-2 border-b border-[#30363d]") do
          div(class: "flex gap-1 flex-wrap") do
            snippets.each_key do |lang|
              button(type: "button",
                     class: "text-[11px] font-mono px-[10px] py-[3px] rounded-md transition-colors cursor-pointer border-0",
                     style: "background:transparent;color:#8b949e",
                     data: { code_tabs_target: "tab",
                             code_tabs_lang_param: lang,
                             action: "click->code-tabs#switch" }) do
                plain LANG_LABELS.fetch(lang, lang)
              end
            end
          end
          div(class: "flex items-center flex-shrink-0") do
            snippets.each do |lang, snippet|
              div(data: { code_tabs_target: "copyArea", lang: lang }) do
                button(type: "button",
                       class: "flex items-center gap-[5px] text-[11px] text-[#8b949e] " \
                              "hover:text-[#c9d1d9] transition-colors cursor-pointer bg-transparent border-0",
                       data: { controller: "clipboard", clipboard_text_value: snippet,
                               action: "click->clipboard#copy" }) do
                  render UI::Icon.new(:copy, class: "w-[11px] h-[11px]")
                  span(data: { clipboard_target: "label" }) { plain "Copy" }
                end
              end
            end
          end
        end

        div(class: "px-5 py-4 overflow-x-auto", data: { code_tabs_target: "panel", lang: "curl" }) do
          pre(class: "text-[12px] leading-[1.7] font-mono m-0 whitespace-pre text-[#c9d1d9]") { yield }
        end
        snippets.reject { |l, _| l == "curl" }.each do |lang, snippet|
          div(class: "px-5 py-4 overflow-x-auto", data: { code_tabs_target: "panel", lang: lang }) do
            pre(class: "text-[12px] leading-[1.7] font-mono m-0 whitespace-pre text-[#c9d1d9]",
                data: { controller: "code-highlight", code_highlight_lang_value: lang }) { plain snippet }
          end
        end
      end
    end

    def qs_response_viewer(label, json_str)
      details(class: "mt-3", open: true,
              style: "border-radius:12px;overflow:hidden;border:1px solid #30363d;background:#0d1117") do
        summary(class: "flex items-center gap-2 px-4 py-[9px] cursor-pointer select-none",
                style: "color:#8b949e;list-style:none") do
          span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:chev_right, class: "w-full h-full") }
          span(class: "text-[10.5px] font-mono") { plain label }
        end
        div(class: "px-5 py-4 overflow-x-auto", style: "border-top:1px solid #30363d") do
          pre(class: "text-[11.5px] leading-[1.6] font-mono m-0 whitespace-pre text-[#c9d1d9]") do
            render_highlighted_json(json_str)
          end
        end
      end
    end

    def render_highlighted_json(json_str)
      json_str.each_line do |raw|
        line = raw.chomp
        if (m = line.match(/\A(\s*)("(?:[^"\\]|\\.)*")(\s*:\s*)(.*?)(,?)\z/))
          indent, key, sep, raw_val, comma = m[1], m[2], m[3], m[4].strip, m[5]
          plain indent
          span(style: "color:#79c0ff") { plain key }
          plain sep
          render_json_token(raw_val)
          plain comma
        else
          plain line
        end
        plain "\n"
      end
    end

    def render_json_token(token)
      case token
      when /\A"(?:[^"\\]|\\.)*"\z/
        span(style: "color:#a5d6ff") { plain token }
      when /\A-?\d+(\.\d+)?\z/
        span(style: "color:#a5d6ff") { plain token }
      when "true", "false", "null"
        span(style: "color:#79c0ff") { plain token }
      else
        plain token
      end
    end

    def qs_idempotency_note
      div(class: "mt-2 flex items-start gap-2") do
        span(class: "flex w-[13px] h-[13px] text-indigo-400 flex-shrink-0 mt-[2px]") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        p(class: "text-[11.5px] text-gray-500 leading-[1.5]") do
          span(class: "font-semibold text-gray-700") { plain "Idempotency-Key" }
          plain " prevents duplicate charges on retries. Use "
          code(class: TYPE_MONO) { plain "uuidgen" }
          plain " (macOS/Linux), "
          code(class: TYPE_MONO) { plain "crypto.randomUUID()" }
          plain " (Node 19+), or "
          code(class: TYPE_MONO) { plain "uuid.uuid4()" }
          plain " (Python). Expires in 24 hours."
        end
      end
    end

    def qs_sandbox_run_section
      div(class: "mt-5 pt-4 border-t border-gray-100",
          data: { controller: "sandbox-run",
                  sandbox_run_url_value: developers_sandbox_run_path }) do
        div(class: "flex items-center gap-3") do
          button(type: "button",
                 class: "flex items-center gap-[6px] text-[12px] font-semibold text-[#3D47F5] " \
                        "border border-indigo-200 rounded-lg px-3 py-[6px] bg-indigo-50 " \
                        "hover:bg-indigo-100 transition-colors cursor-pointer",
                 data: { sandbox_run_target: "btn", action: "click->sandbox-run#run" }) do
            span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
            plain "Run in sandbox"
          end
          span(class: "text-[11.5px] text-gray-400") { plain "Creates a live test session and shows the real response" }
        end
        div(class: "mt-3 bg-[#0d1117] rounded-xl overflow-hidden",
            style: "display:none",
            data: { sandbox_run_target: "result" }) do
          div(class: "flex items-center justify-between px-4 py-2 border-b border-[#30363d]") do
            span(class: "text-[10.5px] font-mono text-[#8b949e]") { plain "RESPONSE  201 Created" }
          end
          div(class: "px-5 py-4 overflow-x-auto") do
            pre(class: "text-[12px] leading-[1.6] font-mono m-0 whitespace-pre text-[#c9d1d9]",
                data: { sandbox_run_target: "code" }) { }
          end
        end
      end
    end

    # ── API Reference panel ───────────────────────────────────────────────────

    def reference_panel
      if @openapi_spec.empty?
        div(class: "#{SURFACE_CARD} px-6 py-16 text-center") do
          span(class: "flex w-8 h-8 text-gray-300 mx-auto mb-3") do
            render UI::Icon.new(:alert_circle, class: "w-full h-full")
          end
          p(class: "text-[13px] font-medium text-gray-500") { plain "Reference unavailable" }
          p(class: TYPE_CAPTION) { plain "Could not load the API spec. Reload to try again." }
        end
        return
      end

      paths   = @openapi_spec["paths"] || {}
      version = @openapi_spec.dig("info", "version") || ""

      # Collect all operations grouped by tag
      by_tag = Hash.new { |h, k| h[k] = [] }
      paths.each do |path, methods|
        methods.each do |verb, op|
          next unless op.is_a?(Hash)
          tag = Array(op["tags"]).first || "Other"
          by_tag[tag] << { verb: verb, path: path, op: op }
        end
      end

      tag_order = TAG_ICON.keys
      sorted_tags = by_tag.keys.sort_by { |t| tag_order.index(t) || 999 }

      div(class: "flex flex-col gap-5") do
        # Header
        div(class: "#{SURFACE_CARD} px-6 py-5 flex items-center justify-between gap-4") do
          div do
            p(class: "text-[14px] font-semibold text-gray-900 mb-0.5") do
              plain "Yagye API "
              span(class: "#{BADGE_XS} #{STATUS_INFO} ml-1") do
                plain version
              end
            end
            p(class: TYPE_CAPTION) { plain "All endpoints use Bearer token auth. Amounts are in minor units (pesewas for GHS)." }
          end
          a(href: "#{core_api_base}/swaggerui", target: "_blank", rel: "noopener",
            class: BTN_SECONDARY) do
            render UI::Icon.new(:external_link, class: ICON_SM)
            plain "Interactive docs"
          end
        end

        # Tag sections
        sorted_tags.each do |tag|
          operations = by_tag[tag]
          icon_name  = TAG_ICON.fetch(tag, :hash)
          ref_section(tag, icon_name, operations)
        end
      end
    end

    def ref_section(tag, icon_name, operations)
      div(class: "#{SURFACE_CARD} overflow-hidden") do
        # Section header
        div(class: "flex items-center gap-3 px-6 py-4 border-b border-gray-100 bg-gray-50/40") do
          div(class: "w-7 h-7 rounded-lg icon-brand flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(icon_name, class: "w-full h-full") }
          end
          p(class: "text-[13px] font-semibold text-gray-900") { plain tag }
          span(class: "#{BADGE_XS} #{STATUS_INFO} ml-1") do
            plain "#{operations.size}"
          end
        end

        # Endpoint rows
        div do
          operations.sort_by { |o| [ o[:path], o[:verb] ] }.each_with_index do |op_data, idx|
            ref_endpoint_row(op_data, last: idx == operations.size - 1)
          end
        end
      end
    end

    def ref_endpoint_row(op_data, last: false)
      verb    = op_data[:verb].upcase
      path    = op_data[:path]
      op      = op_data[:op]
      summary = op["summary"].to_s
      desc    = op["description"].to_s.presence
      badge   = METHOD_BADGE.fetch(op_data[:verb], METHOD_BADGE["get"])

      border_cls = last ? "" : "border-b border-gray-100"

      div(class: "flex items-start gap-4 px-6 py-[13px] hover:bg-gray-50/60 transition-colors #{border_cls}") do
        # Method badge
        span(
          class: "flex-shrink-0 mt-[1px] text-[10px] font-bold font-mono px-[7px] py-[3px] rounded-md w-[44px] text-center",
          style: "background: #{badge[:bg]}; color: #{badge[:color]}"
        ) { plain badge[:text] }

        # Path
        code(class: "flex-shrink-0 text-[12px] font-mono text-gray-700 mt-[2px] hidden sm:block w-[280px] truncate") do
          path.split("/").each_with_index do |segment, i|
            if segment.start_with?("{")
              span(style: "color: #d97706") { plain "/#{segment}" }
            elsif i > 0
              plain "/#{segment}"
            else
              plain segment
            end
          end
        end

        # Summary + description
        div(class: "flex-1 min-w-0") do
          p(class: "text-[12.5px] font-medium text-gray-800 leading-snug") { plain summary }
          p(class: "#{TYPE_CAPTION} mt-[2px] leading-snug") { plain desc } if desc
        end

        # Auth badge
        if op["security"].present?
          span(class: "flex-shrink-0 mt-[2px] text-[9.5px] font-semibold px-[6px] py-[2px] " \
                      "rounded-full hidden lg:inline-flex items-center gap-1",
               style: "background: rgba(61,71,245,0.07); color: #3D47F5") do
            span(class: "flex w-[9px] h-[9px]") { render UI::Icon.new(:lock, class: "w-full h-full") }
            plain "Bearer"
          end
        end
      end
    end

    def core_api_base
      ENV.fetch("CORE_API_URL", "http://localhost:4000")
    end

    def reveal_key_banner
      div(class: "mb-5 bg-emerald-50 border border-emerald-200 rounded-2xl overflow-hidden") do
        div(class: "flex items-start justify-between gap-3 px-6 py-4 border-b border-emerald-100") do
          div(class: "flex items-start gap-3") do
            span(class: "flex w-4 h-4 text-emerald-500 flex-shrink-0 mt-[2px]") do
              render UI::Icon.new(:check_circle, class: "w-full h-full")
            end
            div do
              p(class: "text-[13px] font-semibold text-emerald-900") { plain "API key created — copy it now" }
              p(class: "#{TYPE_CAPTION} text-emerald-700 mt-[2px]") do
                plain "This is the only time your full key is shown. Once you leave or refresh this page, it cannot be recovered."
              end
            end
          end
          a(href: developers_path(tab: "api_keys"),
            class: "flex-shrink-0 flex items-center gap-[6px] text-[11.5px] font-semibold " \
                   "text-emerald-700 border border-emerald-300 rounded-lg px-3 py-[6px] " \
                   "bg-white hover:bg-emerald-50 transition-colors no-underline",
            data: { turbo_action: "replace" }) do
            plain "Done, dismiss"
          end
        end
        div(class: "px-6 py-4 flex items-center gap-3") do
          code(class: "flex-1 min-w-0 font-mono text-[12.5px] text-emerald-900 " \
                      "bg-emerald-100/60 rounded-xl px-4 py-3 select-all break-all") do
            plain @reveal_key.to_s
          end
          button(type: "button",
                 class: "flex-shrink-0 flex items-center gap-[6px] text-[12px] font-semibold " \
                        "text-emerald-700 border border-emerald-300 rounded-lg px-3 py-2 " \
                        "bg-white hover:bg-emerald-50 transition-colors cursor-pointer",
                 data: { controller: "clipboard", clipboard_text_value: @reveal_key.to_s,
                         action: "click->clipboard#copy" }) do
            render UI::Icon.new(:copy, class: "w-[13px] h-[13px]")
            span(data: { clipboard_target: "label" }) { plain "Copy key" }
          end
        end
      end
    end

    def sandbox_enabled?
      @sandbox_enabled
    end

    def test_mode_notice
      sandbox = sandbox_enabled?

      div(class: "mb-5 #{SURFACE_CARD} overflow-hidden") do
        # ── header ──────────────────────────────────────────────────────────
        div(class: "flex items-center justify-between px-5 py-[13px] border-b border-gray-100") do
          div(class: "flex items-center gap-2") do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:layers, class: "w-full h-full")
            end
            p(class: "text-[12.5px] font-bold text-gray-800") { plain "Test environment" }
          end
          if sandbox
            span(class: "#{BADGE} #{STATUS_INFO}") { plain "PSP Sandbox active" }
          else
            span(class: "#{BADGE} #{STATUS_NEUTRAL}") { plain "Yagye Simulation" }
          end
        end

        # ── body ─────────────────────────────────────────────────────────────
        div(class: "px-5 py-4") do
          sandbox ? sandbox_mode_body : simulation_mode_body
        end
      end
    end

    def simulation_mode_body
      div(class: "flex flex-col gap-4") do
        # explanation
        div(class: "flex items-start gap-2.5") do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0 mt-[1px]") do
            render UI::Icon.new(:settings, class: "w-full h-full")
          end
          div do
            p(class: "text-[12.5px] font-semibold text-gray-800 leading-snug") { plain "Yagye Simulation" }
            p(class: "text-[11.5px] text-gray-500 mt-[2px] leading-[1.5]") do
              plain "All transactions are handled by Yagye's internal simulator — no external network calls, " \
                    "instant synthetic responses."
            end
          end
        end

        # test MSISDNs
        div(class: "rounded-xl border border-gray-100 overflow-hidden") do
          div(class: "px-4 py-2.5 bg-gray-50 border-b border-gray-100") do
            p(class: "text-[10.5px] font-bold text-gray-500 uppercase tracking-wide") { plain "Test MSISDNs (Mobile Money)" }
          end
          div do
            sim_msisdn_row("024 100 0001", "MTN MoMo",    "success",            last: false)
            sim_msisdn_row("024 100 0002", "MTN MoMo",    "insufficient_funds", last: false)
            sim_msisdn_row("050 100 0001", "Telecel",     "success",            last: false)
            sim_msisdn_row("057 100 0001", "AirtelTigo",  "success",            last: true)
          end
        end

        # sandbox unlock note
        div(class: "flex items-start gap-2 px-3 py-2.5 rounded-xl border border-amber-100 bg-amber-50") do
          span(class: "flex w-[12px] h-[12px] text-amber-500 flex-shrink-0 mt-[1px]") do
            render UI::Icon.new(:lock, class: "w-full h-full")
          end
          p(class: "text-[11.5px] text-amber-700 leading-[1.5]") do
            plain "PSP Sandbox access (real MTN MoMo, Paystack & Flutterwave test environments) is enabled by the Yagye team " \
                  "once your KYB application is submitted."
          end
        end
      end
    end

    def sim_msisdn_row(msisdn, provider, outcome, last:)
      outcome_style = case outcome
      when "success"            then [ "text-green-700",  "bg-green-50",  "border-green-100",  "Success" ]
      when "insufficient_funds" then [ "text-amber-700",  "bg-amber-50",  "border-amber-100",  "Insufficient funds" ]
      when "failed"             then [ "text-red-700",    "bg-red-50",    "border-red-100",    "Failed" ]
      else                           [ "text-gray-600",   "bg-gray-100",  "border-gray-200",   outcome.humanize ]
      end
      border_cls = last ? "" : "border-b border-gray-100"

      div(class: "flex items-center justify-between px-4 py-[9px] #{border_cls}") do
        div(class: "flex items-center gap-2.5") do
          code(class: "text-[12px] font-mono font-semibold text-gray-800") { plain msisdn }
          span(class: "text-[11px] text-gray-400") { plain provider }
        end
        span(class: "inline-flex items-center px-2 py-[2px] rounded-full text-[10.5px] font-semibold " \
                    "#{outcome_style[0]} #{outcome_style[1]} border #{outcome_style[2]}") do
          plain outcome_style[3]
        end
      end
    end

    def sandbox_mode_body
      div(class: "flex flex-col gap-4") do
        # explanation
        div(class: "flex items-start gap-2.5") do
          span(class: "flex w-[13px] h-[13px] text-indigo-400 flex-shrink-0 mt-[1px]") do
            render UI::Icon.new(:globe, class: "w-full h-full")
          end
          div do
            p(class: "text-[12.5px] font-semibold text-gray-800 leading-snug") { plain "PSP Sandbox" }
            p(class: "text-[11.5px] text-gray-500 mt-[2px] leading-[1.5]") do
              plain "Transactions marked "
              code(class: "text-[11px] font-mono bg-gray-100 px-[4px] py-[1px] rounded") { plain "mode: test" }
              plain " now route to real provider test environments. No real money moves — but external systems are contacted."
            end
          end
        end

        # active providers
        div(class: "rounded-xl border border-gray-100 overflow-hidden") do
          div(class: "px-4 py-2.5 bg-gray-50 border-b border-gray-100") do
            p(class: "text-[10.5px] font-bold text-gray-500 uppercase tracking-wide") { plain "Active sandbox providers" }
          end
          sandbox_provider_row("MTN MoMo sandbox",    "Ghana / MoMo",  "#ffcc00", last: false)
          sandbox_provider_row("Paystack test mode",  "Ghana / Card",  "#00c3f7", last: false)
          sandbox_provider_row("Flutterwave sandbox", "Ghana / Card",  "#f5a623", last: true)
        end

        # simulator override note
        div(class: "flex items-start gap-2 px-3 py-2.5 rounded-xl border border-gray-100 bg-gray-50") do
          span(class: "flex w-[12px] h-[12px] text-gray-400 flex-shrink-0 mt-[1px]") do
            render UI::Icon.new(:settings, class: "w-full h-full")
          end
          p(class: "text-[11.5px] text-gray-500 leading-[1.5]") do
            plain "To force a synthetic response without a real network call, set "
            code(class: "text-[11px] font-mono bg-white border border-gray-200 px-[4px] py-[1px] rounded") { plain "simulator: true" }
            plain " on any transaction payload."
          end
        end
      end
    end

    def sandbox_provider_row(name, region, dot_color, last:)
      border_cls = last ? "" : "border-b border-gray-100"
      div(class: "flex items-center gap-3 px-4 py-[9px] #{border_cls}") do
        span(class: "w-2 h-2 rounded-full flex-shrink-0 inline-block",
             style: "background: #{dot_color}")
        p(class: "flex-1 text-[12px] font-medium text-gray-800") { plain name }
        span(class: "text-[11px] text-gray-400") { plain region }
        span(class: "inline-flex items-center px-2 py-[2px] rounded-full text-[10.5px] font-semibold " \
                    "text-green-700 bg-green-50 border border-green-100") { plain "Active" }
      end
    end

    # ── Webhooks panel ────────────────────────────────────────────────────────

    def reveal_webhook_secret_banner
      div(class: "mb-5 bg-emerald-50 border border-emerald-200 rounded-2xl overflow-hidden") do
        div(class: "flex items-start justify-between gap-3 px-6 py-4 border-b border-emerald-100") do
          div(class: "flex items-start gap-3") do
            span(class: "flex w-4 h-4 text-emerald-500 flex-shrink-0 mt-[2px]") do
              render UI::Icon.new(:check_circle, class: "w-full h-full")
            end
            div do
              p(class: "text-[13px] font-semibold text-emerald-900") { plain "Signing secret — copy it now" }
              p(class: "#{TYPE_CAPTION} text-emerald-700 mt-[2px]") do
                plain "Use this secret to verify webhook signatures (X-Yagye-Signature header). " \
                      "It is shown only once and cannot be recovered."
              end
            end
          end
          a(href: developers_path(tab: "webhooks"),
            class: "flex-shrink-0 flex items-center gap-[6px] text-[11.5px] font-semibold " \
                   "text-emerald-700 border border-emerald-300 rounded-lg px-3 py-[6px] " \
                   "bg-white hover:bg-emerald-50 transition-colors no-underline",
            data: { turbo_action: "replace" }) do
            plain "Done, dismiss"
          end
        end
        div(class: "px-6 py-4 flex items-center gap-3") do
          code(class: "flex-1 min-w-0 font-mono text-[12.5px] text-emerald-900 " \
                      "bg-emerald-100/60 rounded-xl px-4 py-3 select-all break-all") do
            plain @reveal_webhook_secret.to_s
          end
          button(type: "button",
                 class: "flex-shrink-0 flex items-center gap-[6px] text-[12px] font-semibold " \
                        "text-emerald-700 border border-emerald-300 rounded-lg px-3 py-2 " \
                        "bg-white hover:bg-emerald-50 transition-colors cursor-pointer",
                 data: { controller: "clipboard",
                         clipboard_text_value: @reveal_webhook_secret.to_s,
                         action: "click->clipboard#copy" }) do
            render UI::Icon.new(:copy, class: "w-[13px] h-[13px]")
            span(data: { clipboard_target: "label" }) { plain "Copy secret" }
          end
        end
      end
    end

    def webhooks_panel
      div do
        render UI::Datatable.new(records: @webhooks,
                                 empty_message: "No webhook endpoints. Add one to receive real-time payment events.") do |t|
          t.header do
            div(class: "flex items-center justify-between w-full") do
              div do
                p(class: TYPE_TITLE) { plain "Webhook endpoints" }
                p(class: "#{TYPE_CAPTION} mt-0.5") { plain "Yagye sends signed POST requests to your endpoints for each event." }
              end
              render UI::Button.new(variant: :primary, href: new_developers_webhook_path,
                                    data: { turbo_frame: "drawer-frame" }) do
                render UI::Icon.new(:plus, class: ICON_SM)
                plain "Add Endpoint"
              end
            end
          end

          t.column("URL")     { |wh| code(class: TYPE_MONO) { plain wh.url } }
          t.column("Events") do |wh|
            events = Array(wh.subscribed_events)
            if events.empty?
              span(class: TYPE_CAPTION) { plain "All events" }
            else
              div(class: "flex flex-wrap gap-1") do
                events.each do |ev|
                  span(class: "inline-flex items-center px-[6px] py-[2px] rounded-[5px] " \
                               "bg-gray-100 text-gray-600 text-[10.5px] font-mono leading-none") do
                    plain ev
                  end
                end
              end
            end
          end
          t.column("Status") do |wh|
            div(class: "flex flex-col gap-1") do
              render UI::StatusBadge.new(status: wh.active ? "active" : "suspended")
              if wh.consecutive_failures.to_i > 0
                span(class: "inline-flex items-center gap-[3px] text-[10px] font-semibold text-amber-600") do
                  span(class: "flex w-[10px] h-[10px] flex-shrink-0") { render UI::Icon.new(:alert_triangle, class: "w-full h-full") }
                  plain "#{wh.consecutive_failures} consecutive failure#{wh.consecutive_failures == 1 ? '' : 's'}"
                end
              end
            end
          end
          t.column("Created") { |wh| span(class: TYPE_CAPTION) { plain fmt_date(wh.created_at) } }

          t.actions do |wh|
            a(href: edit_developers_webhook_path(wh.endpoint_id),
              class: DROPDOWN_ITEM,
              data: { turbo_frame: "drawer-frame" }) do
              render UI::Icon.new(:edit, class: ICON_SM)
              plain "Edit"
            end
            form(action: test_developers_webhook_path(wh.endpoint_id), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit", class: DROPDOWN_ITEM) do
                render UI::Icon.new(:refresh, class: ICON_SM)
                plain "Send test"
              end
            end
            toggle_label = wh.active ? "Disable" : "Re-enable"
            toggle_icon  = wh.active ? :x : :check
            if wh.active
              a(href: disable_modal_developers_webhook_path(wh.endpoint_id),
                class: DROPDOWN_ITEM,
                data: { turbo_frame: "modal-frame" }) do
                render UI::Icon.new(toggle_icon, class: ICON_SM)
                plain toggle_label
              end
            else
              form(action: toggle_developers_webhook_path(wh.endpoint_id), method: "post") do
                input(type: "hidden", name: "_method",            value: "patch")
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit", class: DROPDOWN_ITEM) do
                  render UI::Icon.new(toggle_icon, class: ICON_SM)
                  plain toggle_label
                end
              end
            end
            a(href: remove_modal_developers_webhook_path(wh.endpoint_id),
              class: DROPDOWN_ITEM_DANGER,
              data: { turbo_frame: "modal-frame" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Remove"
            end
          end
        end

        signing_secret_info
      end
    end

    def signing_secret_info
      div(class: "bg-gray-50 border border-gray-100 rounded-[14px] px-6 py-5 mt-5 flex flex-col gap-3") do
        div do
          p(class: "#{TYPE_BODY_MD} mb-1.5") { plain "Webhook signature verification" }
          p(class: TYPE_CAPTION) do
            plain "Every payload is signed using HMAC-SHA256. Always verify the "
            code(class: TYPE_MONO) { plain "X-Yagye-Signature" }
            plain " header before fulfilling an order."
          end
          a(href: developers_path(tab: "quickstart"), class: "#{TYPE_CAPTION} text-[#3D47F5] no-underline mt-2 inline-flex items-center gap-1") do
            plain "View verification guide"
            span(class: "flex w-3 h-3") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
          end
        end
        div(class: "border-t border-gray-200 pt-3") do
          p(class: "#{TYPE_CAPTION} text-amber-700") do
            plain "After updating an endpoint URL, click "
            span(class: "font-semibold") { plain "Send test" }
            plain " to confirm delivery to the new address. Any events already queued will complete their first attempt to the previous URL before retries pick up the change."
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
        t.column("HTTP") do |d|
          if d.response_status
            color = d.response_status.between?(200, 299) ? "#16a34a" : "#dc2626"
            bg    = d.response_status.between?(200, 299) ? "#f0fdf4" : "#fef2f2"
            span(class: "text-[11.5px] font-semibold px-2 py-[2px] rounded-full font-mono",
                 style: "color:#{color};background:#{bg}") { plain d.response_status.to_s }
          else
            span(class: TYPE_CAPTION) { plain "—" }
          end
        end
        t.column("Duration") { |d| span(class: TYPE_CAPTION) { plain d.formatted_duration } }
        t.column("Attempt")  { |d| span(class: TYPE_CAPTION) { plain d.attempt.to_s } }
        t.column("Sent")     { |d| span(class: TYPE_CAPTION) { plain fmt_datetime(d.last_applied_at) } }

        t.actions do |d|
          a(href: developers_delivery_path(d),
            class: DROPDOWN_ITEM,
            data: { turbo_frame: "drawer-frame" }) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "Inspect"
          end
          if d.state == "failed"
            form(action: retry_developers_delivery_path(d), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit", class: DROPDOWN_ITEM) do
                render UI::Icon.new(:refresh, class: ICON_SM)
                plain "Retry"
              end
            end
          end
        end
      end
    end
  end
end
