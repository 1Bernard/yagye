defmodule YagyeCheckoutWeb.Live.CheckoutLive do
  use Phoenix.LiveView, layout: false
  import Phoenix.HTML, only: [raw: 1]

  alias YagyeCheckout.CoreClient

  @poll_ms 3_000
  @max_polls 40

  @mtn_prefixes ~w[024 054 055 059 025 053 058]
  @telecel_prefixes ~w[020 050]
  @airteltigo_prefixes ~w[026 056 027 057]

  @networks [
    %{id: "MTN",        label: "MTN MoMo",   css: "mtn"},
    %{id: "Telecel",    label: "Telecel Cash", css: "telecel"},
    %{id: "AirtelTigo", label: "AT Money",    css: "at"}
  ]

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case CoreClient.get_session(token) do
      {:ok, session} -> {:ok, init_from_session(socket, session)}
      {:error, :not_found} -> {:ok, base_assigns(socket, :not_found)}
      {:error, _} -> {:ok, base_assigns(socket, :error)}
    end
  end

  # ── Event Handlers ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, selected_method: method, error: nil, phone_error: nil)}
  end

  def handle_event("select_network", %{"network" => network}, socket) do
    {:noreply, assign(socket, selected_network: network, error: nil, phone_error: nil, detected_network: network)}
  end

  def handle_event("change_phone", %{"phone" => phone}, socket) do
    stripped = String.replace(phone, ~r/\D/, "")
    network = if String.length(stripped) >= 3, do: detect_network(stripped), else: nil
    new_selected = if network, do: network, else: socket.assigns.selected_network

    {:noreply,
     assign(socket,
       phone: phone,
       detected_network: network,
       selected_network: new_selected,
       phone_error: nil
     )}
  end

  def handle_event("submit_checkout", params, socket) do
    collection_errors = validate_collection(params, socket.assigns)

    if collection_errors != %{} do
      {:noreply, assign(socket, collection_errors: collection_errors)}
    else
      phone =
        Map.get(params, "phone", socket.assigns.phone)
        |> to_string()
        |> String.replace(~r/[\s\-()]/, "")

      case validate_phone(phone, socket.assigns.selected_network) do
        {:error, msg} -> {:noreply, assign(socket, phone_error: msg)}
        :ok ->
          socket =
            assign(socket,
              customer_email: String.trim(params["customer_email"] || ""),
              customer_phone: String.trim(params["customer_phone"] || ""),
              customer_name: String.trim(params["customer_name"] || ""),
              collection_errors: %{}
            )

          submit_payment(socket, phone)
      end
    end
  end

  def handle_info({:auto_redirect, url}, socket) do
    {:noreply, push_event(socket, "redirect_to", %{url: url})}
  end

  @impl true
  def handle_info(:poll, %{assigns: %{poll_count: n}} = socket) when n >= @max_polls do
    {:noreply,
     assign(socket,
       page_state: :form,
       error: "Payment is taking longer than expected. Please check your phone for the USSD prompt or try again."
     )}
  end

  def handle_info(:poll, socket) do
    %{assigns: %{payment_public_id: pay_id, session_public_id: sid, poll_count: n}} = socket

    case CoreClient.get_payment_state(pay_id) do
      {:ok, %{"state" => "succeeded"}} ->
        finalize(socket, sid, pay_id)

      {:ok, %{"state" => state}} when state in ["failed", "cancelled"] ->
        {:noreply,
         assign(socket,
           page_state: :form,
           error: "Payment was declined or cancelled. Please check your account and try again."
         )}

      _ ->
        Process.send_after(self(), :poll, @poll_ms)
        {:noreply, assign(socket, poll_count: n + 1)}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="co-checkout-container">

      <%!-- ── Terminal Screens ── --%>
      <%= case @page_state do %>

        <% :processing -> %>
          <div class="co-panel co-terminal-panel">
            <div class="co-spinner"><div class="co-spinner-ring"></div></div>
            <h2 class="co-terminal-title">Processing your payment…</h2>
            <p class="co-terminal-desc">
              Please check your phone. If you received a USSD prompt on <strong>{@phone}</strong>, enter your PIN to approve.
            </p>
            <div class="co-progress-bar"><div class="co-progress-fill"></div></div>
            <p class="co-terminal-hint">This page updates automatically once your payment is confirmed.</p>
          </div>

        <% :done -> %>
          <% {whole, cents} = format_amount_parts(@total_amount) %>
          <div class="co-panel co-terminal-panel co-terminal-panel--success">
            <div class="co-success-icon-wrap">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#16a34a" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>
              </svg>
            </div>
            <h2 class="co-terminal-title">Payment Successful!</h2>
            <div class="co-terminal-amount">{currency_symbol(@currency)}{whole}.{cents}</div>
            <p class="co-terminal-desc">Your transaction has been confirmed. A receipt will be sent to you shortly.</p>
            <div class="co-receipt-box">
              <div class="co-receipt-row">
                <span>Reference</span>
                <span class="co-receipt-mono">{@session && @session["public_id"]}</span>
              </div>
              <div class="co-receipt-row">
                <span>Method</span>
                <span>{method_label(@selected_method)}</span>
              </div>
              <div class="co-receipt-row">
                <span>Status</span>
                <span class="co-badge-paid">Paid</span>
              </div>
            </div>
            <%= if @success_url && external_url?(@success_url) do %>
              <a href={@success_url} class="co-btn-primary">Return to Merchant</a>
            <% end %>
          </div>

        <% :expired -> %>
          <div class="co-panel co-terminal-panel">
            <div class="co-warn-icon-wrap">
              <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#d97706" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
              </svg>
            </div>
            <h2 class="co-terminal-title">Payment Link Expired</h2>
            <p class="co-terminal-desc">This checkout session has expired for security reasons. Return to the merchant for a fresh link.</p>
          </div>

        <% :cancelled -> %>
          <div class="co-panel co-terminal-panel">
            <div class="co-warn-icon-wrap">
              <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#d97706" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="10"/>
                <line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/>
              </svg>
            </div>
            <h2 class="co-terminal-title">Payment Cancelled</h2>
            <p class="co-terminal-desc">This payment was cancelled. Return to the merchant if you'd like to try again.</p>
          </div>

        <% :not_found -> %>
          <div class="co-panel co-terminal-panel">
            <div class="co-warn-icon-wrap">
              <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#d97706" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="10"/>
                <line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
              </svg>
            </div>
            <h2 class="co-terminal-title">Link Not Found</h2>
            <p class="co-terminal-desc">This payment link is invalid or doesn't exist. Please request a new one from the merchant.</p>
          </div>

        <% :error -> %>
          <div class="co-panel co-terminal-panel">
            <div class="co-warn-icon-wrap">
              <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#d97706" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polygon points="7.86 2 16.14 2 22 7.86 22 16.14 16.14 22 7.86 22 2 16.14 2 7.86 7.86 2"/>
                <line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
              </svg>
            </div>
            <h2 class="co-terminal-title">Something Went Wrong</h2>
            <p class="co-terminal-desc">We couldn't load this page. Please try again or contact the merchant.</p>
          </div>

        <% _ -> %>
          <%!-- ── Two-Column Layout ── --%>
          <div class="co-grid">

            <%!-- ── LEFT: Payment Options ── --%>
            <main class="co-main-column">
              <div class="co-panel co-payment-panel">

                <div class="co-panel-header">
                  <div class="co-panel-title-wrap">
                    <div class="co-title-icon">
                      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="1" y="4" width="22" height="16" rx="2" ry="2"/>
                        <line x1="1" y1="10" x2="23" y2="10"/>
                      </svg>
                    </div>
                    <h1 class="co-panel-title">Select Payment Option</h1>
                  </div>
                  <span class="co-methods-count">
                    {length(@methods)} {if length(@methods) == 1, do: "option", else: "options"} available
                  </span>
                </div>

                <%= if @error do %>
                  <div class="co-alert co-alert--error">
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                      <circle cx="12" cy="12" r="10"/>
                      <line x1="12" y1="8" x2="12" y2="12"/>
                      <line x1="12" y1="16" x2="12.01" y2="16"/>
                    </svg>
                    <span>{@error}</span>
                  </div>
                <% end %>

                <form phx-submit="submit_checkout" class="co-options-form">

                  <%!-- ── Customer Details ── --%>
                  <%= if @collect_name or @collect_email or @collect_phone do %>
                    <div class="co-customer-section">
                      <div class="co-customer-heading">
                        <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                          <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
                          <circle cx="12" cy="7" r="4"/>
                        </svg>
                        <span>Your details</span>
                      </div>
                      <div class="co-customer-fields">
                        <%= if @collect_name do %>
                          <div class="co-field">
                            <label class="co-field-label" for="customer_name">Full name</label>
                            <input
                              id="customer_name"
                              name="customer_name"
                              type="text"
                              class={"co-input#{if @collection_errors["name"], do: " co-input--error"}"}
                              value={@customer_name}
                              placeholder="John Doe"
                              autocomplete="name"
                            />
                            <%= if @collection_errors["name"] do %>
                              <span class="co-error-text">
                                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                  <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
                                </svg>
                                {@collection_errors["name"]}
                              </span>
                            <% end %>
                          </div>
                        <% end %>

                        <%= if @collect_email do %>
                          <div class="co-field">
                            <label class="co-field-label" for="customer_email">Email address</label>
                            <input
                              id="customer_email"
                              name="customer_email"
                              type="email"
                              class={"co-input#{if @collection_errors["email"], do: " co-input--error"}"}
                              value={@customer_email}
                              placeholder="you@example.com"
                              autocomplete="email"
                              inputmode="email"
                            />
                            <%= if @collection_errors["email"] do %>
                              <span class="co-error-text">
                                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                  <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
                                </svg>
                                {@collection_errors["email"]}
                              </span>
                            <% end %>
                          </div>
                        <% end %>

                        <%= if @collect_phone do %>
                          <div class="co-field">
                            <label class="co-field-label" for="customer_phone">Phone number</label>
                            <input
                              id="customer_phone"
                              name="customer_phone"
                              type="tel"
                              class={"co-input#{if @collection_errors["phone"], do: " co-input--error"}"}
                              value={@customer_phone}
                              placeholder="+233 24 000 0000"
                              autocomplete="tel"
                              inputmode="tel"
                            />
                            <%= if @collection_errors["phone"] do %>
                              <span class="co-error-text">
                                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                  <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
                                </svg>
                                {@collection_errors["phone"]}
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>

                  <%!-- ── Mobile Money — live ── --%>
                  <%= if method_enabled?(@methods, "mobile_money") do %>
                    <div class={"co-option-card#{if @selected_method == "mobile_money", do: " co-option-card--active"}"}>
                      <div class="co-option-header" phx-click="select_method" phx-value-method="mobile_money">
                        <label class="co-radio-label">
                          <input type="radio" name="payment_method" value="mobile_money"
                            checked={@selected_method == "mobile_money"} class="co-radio-input" />
                          <span class="co-radio-custom"></span>
                          <span class="co-option-name">Mobile Money</span>
                        </label>
                        <div class="co-telco-logos">
                          <span class="co-logo-badge" title="MTN MoMo">
                            <svg width="24" height="24" viewBox="0 0 32 32" fill="none">
                              <rect width="32" height="32" rx="16" fill="#FFCC00"/>
                              <path d="M7 16c0-4.97 4.03-9 9-9s9 4.03 9 9-4.03 9-9 9-9-4.03-9-9z" fill="#002B49"/>
                              <path d="M12 19.5v-7l3 4.5 3-4.5v7" stroke="#FFCC00" stroke-width="2" stroke-linecap="round"/>
                            </svg>
                          </span>
                          <span class="co-logo-badge" title="Telecel Cash">
                            <svg width="24" height="24" viewBox="0 0 32 32" fill="none">
                              <circle cx="16" cy="16" r="16" fill="#E60000"/>
                              <circle cx="16" cy="16" r="10" stroke="#FFF" stroke-width="2.5" fill="none"/>
                              <path d="M16 11v10M12 15h8" stroke="#FFF" stroke-width="2.5" stroke-linecap="round"/>
                            </svg>
                          </span>
                          <span class="co-logo-badge" title="AT Money">
                            <svg width="24" height="24" viewBox="0 0 32 32" fill="none">
                              <circle cx="16" cy="16" r="16" fill="#1A2B4C"/>
                              <path d="M0 16a16 16 0 0 0 32 0H0z" fill="#ED1C24"/>
                              <text x="16" y="19" font-family="Inter,sans-serif" font-size="12" font-weight="900" fill="#FFF" text-anchor="middle">at</text>
                            </svg>
                          </span>
                        </div>
                      </div>

                      <%= if @selected_method == "mobile_money" do %>
                        <div class="co-option-body">
                          <div class="co-field-group">
                            <label class="co-field-label">Choose Network Provider</label>
                            <div class="co-net-tiles">
                              <%= for net <- @networks do %>
                                <button
                                  type="button"
                                  class={"co-net-tile co-net-tile--#{net.css}#{if @selected_network == net.id, do: " co-net-tile--selected"}"}
                                  phx-click="select_network"
                                  phx-value-network={net.id}
                                >
                                  <span class="co-net-logo-wrap">
                                    {raw(network_svg(net.id))}
                                  </span>
                                  <div class="co-net-info">
                                    <span class="co-net-name">{net.label}</span>
                                    <span class="co-net-sub">{network_prefix_hint(net.id)}</span>
                                  </div>
                                  <%= if @selected_network == net.id do %>
                                    <span class="co-net-check">
                                      <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                                        <polyline points="20 6 9 17 4 12"/>
                                      </svg>
                                    </span>
                                  <% end %>
                                </button>
                              <% end %>
                            </div>
                          </div>

                          <div class="co-field">
                            <label class="co-field-label" for="phone">
                              {if @selected_network, do: "#{network_label(@selected_network)} Number", else: "Mobile Money Number"}
                            </label>
                            <div class={"co-phone-box#{if @phone_error, do: " co-phone-box--error"}"}>
                              <span class="co-flag-pill">
                                <span class="co-flag">🇬🇭</span>
                                <span class="co-calling-code">+233</span>
                              </span>
                              <input
                                id="phone"
                                name="phone"
                                type="tel"
                                class="co-input co-phone-input"
                                value={@phone}
                                placeholder="024 000 0000"
                                autocomplete="tel-national"
                                inputmode="numeric"
                                maxlength="10"
                                phx-change="change_phone"
                              />
                              <%= if @detected_network do %>
                                <span class={"co-detected-badge co-detected-badge--#{network_css_key(@detected_network)}"}>
                                  {@detected_network}
                                </span>
                              <% end %>
                            </div>
                            <%= if @phone_error do %>
                              <span class="co-error-text">
                                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                  <circle cx="12" cy="12" r="10"/>
                                  <line x1="12" y1="8" x2="12" y2="12"/>
                                  <line x1="12" y1="16" x2="12.01" y2="16"/>
                                </svg>
                                {@phone_error}
                              </span>
                            <% end %>
                            <p class="co-field-hint">A USSD prompt will appear. Approve with your MoMo PIN.</p>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <%!-- ── Card — coming soon ── --%>
                  <%= if method_enabled?(@methods, "card") do %>
                    <div class={"co-option-card#{if @selected_method == "card", do: " co-option-card--active"}"}>
                      <div class="co-option-header" phx-click="select_method" phx-value-method="card">
                        <label class="co-radio-label">
                          <input type="radio" name="payment_method" value="card"
                            checked={@selected_method == "card"} class="co-radio-input" />
                          <span class="co-radio-custom"></span>
                          <span class="co-option-name">Credit / Debit Card</span>
                        </label>
                        <div class="co-card-logos">
                          {raw(card_brand_svg("visa"))}
                          {raw(card_brand_svg("mastercard"))}
                          {raw(card_brand_svg("verve"))}
                        </div>
                      </div>
                      <%= if @selected_method == "card" do %>
                        <div class="co-option-body">
                          <div class="co-coming-soon">
                            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                              <rect x="1" y="4" width="22" height="16" rx="2" ry="2"/>
                              <line x1="1" y1="10" x2="23" y2="10"/>
                            </svg>
                            <div>
                              <p class="co-coming-soon-title">Card payments launching soon</p>
                              <p class="co-coming-soon-desc">We're finalising card processing. Use Mobile Money to pay now.</p>
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <%!-- ── Bank Transfer — coming soon ── --%>
                  <%= if method_enabled?(@methods, "bank_transfer") do %>
                    <div class={"co-option-card#{if @selected_method == "bank_transfer", do: " co-option-card--active"}"}>
                      <div class="co-option-header" phx-click="select_method" phx-value-method="bank_transfer">
                        <label class="co-radio-label">
                          <input type="radio" name="payment_method" value="bank_transfer"
                            checked={@selected_method == "bank_transfer"} class="co-radio-input" />
                          <span class="co-radio-custom"></span>
                          <span class="co-option-name">Bank Transfer</span>
                        </label>
                        <span style="color:var(--muted-text)">
                          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                            <line x1="3" y1="22" x2="21" y2="22"/>
                            <line x1="6" y1="18" x2="6" y2="11"/>
                            <line x1="10" y1="18" x2="10" y2="11"/>
                            <line x1="14" y1="18" x2="14" y2="11"/>
                            <line x1="18" y1="18" x2="18" y2="11"/>
                            <polygon points="12 2 20 7 4 7"/>
                          </svg>
                        </span>
                      </div>
                      <%= if @selected_method == "bank_transfer" do %>
                        <div class="co-option-body">
                          <div class="co-coming-soon">
                            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                              <line x1="3" y1="22" x2="21" y2="22"/>
                              <line x1="6" y1="18" x2="6" y2="11"/>
                              <line x1="10" y1="18" x2="10" y2="11"/>
                              <line x1="14" y1="18" x2="14" y2="11"/>
                              <line x1="18" y1="18" x2="18" y2="11"/>
                              <polygon points="12 2 20 7 4 7"/>
                            </svg>
                            <div>
                              <p class="co-coming-soon-title">Instant virtual accounts launching soon</p>
                              <p class="co-coming-soon-desc">GhIPSS instant bank transfer is coming. Use Mobile Money for now.</p>
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <%!-- ── Pay Button ── --%>
                  <% {whole, cents} = format_amount_parts(@total_amount) %>
                  <button
                    type="submit"
                    class="co-btn-pay"
                    disabled={@selected_method != "mobile_money"}
                    phx-disable-with="Securing payment…"
                  >
                    Pay {currency_symbol(@currency)}{whole}.{cents}
                  </button>

                  <div class="co-trust-strip">
                    <span>
                      <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                      </svg>
                      256-bit SSL
                    </span>
                    <span>&middot;</span>
                    <span>Bank-grade security</span>
                    <span>&middot;</span>
                    <span>Instant settlement</span>
                  </div>

                  <%= if @cancel_url && external_url?(@cancel_url) do %>
                    <div class="co-cancel-wrap">
                      <a href={@cancel_url} class="co-cancel-link">
                        <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                          <line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/>
                        </svg>
                        Cancel and return
                      </a>
                    </div>
                  <% end %>
                </form>
              </div>
            </main>

            <%!-- ── RIGHT: Order Summary ── --%>
            <aside class="co-sidebar-column">

              <%!-- Merchant brand + security --%>
              <div class="co-panel co-merchant-panel">
                <div class="co-merchant-brand">
                  <%= if @logo_url && @logo_url != "" do %>
                    <img src={@logo_url} alt="Merchant logo" class="co-merchant-logo" />
                  <% else %>
                    <div class="co-merchant-icon">
                      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="3" y="11" width="18" height="11" rx="2"/>
                        <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                      </svg>
                    </div>
                  <% end %>
                  <span class="co-merchant-name">{merchant_brand_name(@session)}</span>
                </div>
                <div class="co-merchant-ssl">
                  <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                  </svg>
                  <span>Secured</span>
                </div>
              </div>

              <%!-- Simple payment — product block --%>
              <%= if @line_items == [] do %>
                <% {w, c} = format_amount_parts(@total_amount) %>
                <div class="co-panel co-product-panel">
                  <div class="co-product-icon">
                    <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                      <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/>
                    </svg>
                  </div>
                  <div class="co-product-info">
                    <span class="co-product-label">You're paying for</span>
                    <span class="co-product-name">{@session && (@session["description"] || "Payment")}</span>
                  </div>
                  <div class="co-product-amount">
                    <span class="co-product-currency">{currency_symbol(@currency)}</span>
                    <span class="co-product-whole">{w}</span>
                    <span class="co-product-cents">.{c}</span>
                  </div>
                </div>
              <% end %>

              <%!-- Line items — only when merchant sent them --%>
              <%= if @line_items != [] do %>
                <div class="co-panel co-cart-panel">
                  <div class="co-sidebar-title-wrap">
                    <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                      <path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/>
                      <line x1="3" y1="6" x2="21" y2="6"/>
                      <path d="M16 10a4 4 0 0 1-8 0"/>
                    </svg>
                    <h2 class="co-sidebar-title">
                      Order ({length(@line_items)} {if length(@line_items) == 1, do: "item", else: "items"})
                    </h2>
                  </div>
                  <div class="co-cart-items-list">
                    <%= for item <- @line_items do %>
                      <% {w, c} = format_amount_parts(item["total_amount"] || item["unit_amount"]) %>
                      <div class="co-cart-item">
                        <div class="co-item-thumb">
                          <%= if item["image_url"] && item["image_url"] != "" do %>
                            <img src={item["image_url"]} alt={item["description"]} class="co-thumb-img" />
                          <% else %>
                            <div class="co-thumb-box">
                              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                                <rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="12" cy="12" r="4"/>
                              </svg>
                            </div>
                          <% end %>
                        </div>
                        <div class="co-item-details">
                          <div class="co-item-top">
                            <span class="co-item-title">{item["description"]}</span>
                          </div>
                          <div class="co-item-bottom">
                            <span class="co-item-qty">Qty {item["quantity"] || 1}</span>
                            <span class="co-item-price">{currency_symbol(@currency)}{w}.{c}</span>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Breakdown + Total — only needed when there are extras or line items --%>
              <%= if @line_items != [] or @tax_amount > 0 or @shipping_amount > 0 or @discount_amount > 0 do %>
                <div class="co-panel co-summary-panel">
                  <div class="co-summary-rows">
                    <%= if @line_items != [] do %>
                      <% {w, c} = format_amount_parts(@subtotal_amount) %>
                      <div class="co-summary-row">
                        <span class="co-summary-label">Subtotal</span>
                        <span class="co-summary-val">{currency_symbol(@currency)}{w}.{c}</span>
                      </div>
                    <% end %>

                    <%= if @tax_amount > 0 do %>
                      <% {w, c} = format_amount_parts(@tax_amount) %>
                      <div class="co-summary-row">
                        <span class="co-summary-label">Tax</span>
                        <span class="co-summary-val">{currency_symbol(@currency)}{w}.{c}</span>
                      </div>
                    <% end %>

                    <%= if @shipping_amount > 0 do %>
                      <% {w, c} = format_amount_parts(@shipping_amount) %>
                      <div class="co-summary-row">
                        <span class="co-summary-label">Shipping</span>
                        <span class="co-summary-val">{currency_symbol(@currency)}{w}.{c}</span>
                      </div>
                    <% end %>

                    <%= if @discount_amount > 0 do %>
                      <% {w, c} = format_amount_parts(@discount_amount) %>
                      <div class="co-summary-row co-summary-row--discount">
                        <span class="co-summary-label">Discount</span>
                        <span class="co-summary-val">−{currency_symbol(@currency)}{w}.{c}</span>
                      </div>
                    <% end %>

                    <div class="co-summary-divider"></div>

                    <% {tot_w, tot_c} = format_amount_parts(@total_amount) %>
                    <div class="co-summary-row co-summary-row--total">
                      <span class="co-total-label">Total due</span>
                      <span class="co-total-val">{currency_symbol(@currency)}{tot_w}.{tot_c}</span>
                    </div>
                  </div>
                </div>
              <% end %>

            </aside>
          </div>

      <% end %>

      <footer class="co-page-footer">
        Powered by <strong>Yagye</strong>
      </footer>
    </div>

    <style>
      :root {
        --brand:        #3D47F5;
        --brand-hover:  #323BD8;
        --brand-subtle: rgba(61,71,245,0.08);
        --brand-glow:   rgba(61,71,245,0.15);
        --canvas:       #F9FAFB;
        --card-bg:      #FFFFFF;
        --ink:          #111827;
        --body-text:    #374151;
        --prose-text:   #4B5563;
        --muted-text:   #6B7280;
        --subtle-text:  #9CA3AF;
        --border:       #F3F4F6;
        --border-med:   #E5E7EB;
        --border-strong:#D1D5DB;
        --success:      #16A34A;
        --success-bg:   #ECFDF5;
        --error:        #DC2626;
        --error-bg:     #FEF2F2;
      }

      .co-checkout-container {
        width: 100%;
        max-width: 1100px;
        margin: 0 auto;
        display: flex;
        flex-direction: column;
        gap: 1.5rem;
      }

      /* ── Merchant Panel ── */
      .co-merchant-panel {
        display: flex; align-items: center; justify-content: space-between;
        padding: 1rem 1.25rem;
      }

      .co-merchant-brand { display: flex; align-items: center; gap: 0.625rem; }

      .co-merchant-icon {
        width: 36px; height: 36px; flex-shrink: 0;
        border-radius: 10px;
        background: var(--brand-subtle);
        color: var(--brand);
        display: flex; align-items: center; justify-content: center;
      }

      .co-merchant-name {
        font-family: 'Plus Jakarta Sans', system-ui, sans-serif;
        font-size: 1rem; font-weight: 800;
        color: var(--ink); letter-spacing: -0.02em;
      }

      .co-merchant-logo {
        width: 36px; height: 36px; flex-shrink: 0;
        border-radius: 10px; object-fit: cover;
        border: 1px solid var(--border-med);
      }

      .co-merchant-ssl {
        display: flex; align-items: center; gap: 0.3rem;
        font-size: 0.6875rem; font-weight: 700;
        color: var(--success);
        background: var(--success-bg);
        border: 1px solid rgba(22,163,74,0.18);
        border-radius: 999px;
        padding: 0.25rem 0.6rem;
      }

      /* ── Product Panel (simple payment) ── */
      .co-product-panel {
        display: flex; align-items: center; gap: 1rem;
        padding: 1.25rem 1.25rem;
      }

      .co-product-icon {
        width: 44px; height: 44px; flex-shrink: 0;
        border-radius: 12px;
        background: var(--brand-subtle);
        color: var(--brand);
        display: flex; align-items: center; justify-content: center;
      }

      .co-product-info {
        flex: 1; display: flex; flex-direction: column; gap: 0.15rem; min-width: 0;
      }

      .co-product-label {
        font-size: 0.6875rem; font-weight: 600;
        color: var(--muted-text); text-transform: uppercase; letter-spacing: 0.04em;
      }

      .co-product-name {
        font-size: 0.9375rem; font-weight: 700; color: var(--ink);
        white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
      }

      .co-product-amount {
        display: flex; align-items: baseline; gap: 0.1rem; flex-shrink: 0;
      }

      .co-product-currency {
        font-size: 0.875rem; font-weight: 700; color: var(--ink);
      }

      .co-product-whole {
        font-family: 'Plus Jakarta Sans', system-ui, sans-serif;
        font-size: 1.375rem; font-weight: 800; color: var(--ink); letter-spacing: -0.02em;
      }

      .co-product-cents {
        font-size: 0.875rem; font-weight: 700; color: var(--muted-text);
      }

      /* ── Grid ── */
      .co-grid {
        display: grid;
        grid-template-columns: 1fr;
        gap: 1.5rem;
        align-items: start;
      }

      @media (min-width: 960px) {
        .co-grid { grid-template-columns: 1.32fr 1fr; gap: 1.75rem; }
      }

      /* ── Panels ── */
      .co-panel {
        background: var(--card-bg);
        border: 1px solid var(--border-med);
        border-radius: 20px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.03), 0 8px 24px -6px rgba(0,0,0,0.04);
        overflow: hidden;
      }

      .co-payment-panel { padding: 1.75rem 2rem; }
      @media (max-width: 640px) { .co-payment-panel { padding: 1.25rem 1rem; } }

      .co-panel-header {
        display: flex; align-items: center; justify-content: space-between;
        margin-bottom: 1.5rem;
      }

      .co-panel-title-wrap { display: flex; align-items: center; gap: 0.625rem; }
      .co-title-icon { color: var(--brand); display: flex; align-items: center; }

      .co-panel-title {
        font-size: 1.125rem; font-weight: 700;
        color: var(--ink); letter-spacing: -0.01em;
      }

      .co-methods-count {
        font-size: 0.75rem; font-weight: 600; color: var(--muted-text);
        background: var(--canvas); border: 1px solid var(--border-med);
        padding: 0.2rem 0.55rem; border-radius: 999px;
      }

      /* ── Alert ── */
      .co-alert {
        display: flex; align-items: flex-start; gap: 0.5rem;
        padding: 0.75rem 1rem; border-radius: 12px; margin-bottom: 1rem;
        font-size: 0.8125rem; font-weight: 500; line-height: 1.5;
      }

      .co-alert--error {
        background: var(--error-bg);
        border: 1px solid #FECACA;
        color: var(--error);
      }

      /* ── Options Accordion ── */
      .co-options-form { display: flex; flex-direction: column; gap: 0.875rem; }

      .co-option-card {
        border: 1px solid var(--border-med);
        border-radius: 14px;
        background: #FFFFFF;
        transition: all 0.2s cubic-bezier(0.16,1,0.3,1);
        overflow: hidden;
      }

      .co-option-card:hover { border-color: var(--border-strong); background: #FAFAFA; }

      .co-option-card--active {
        border: 2px solid var(--brand) !important;
        background: #FFFFFF !important;
        box-shadow: 0 4px 16px var(--brand-glow);
      }

      .co-option-header {
        display: flex; align-items: center; justify-content: space-between;
        padding: 1rem 1.25rem; cursor: pointer; user-select: none;
      }

      .co-radio-label { display: flex; align-items: center; gap: 0.75rem; cursor: pointer; }
      .co-radio-input { display: none; }

      .co-radio-custom {
        width: 18px; height: 18px; border-radius: 50%;
        border: 2px solid var(--border-strong);
        display: flex; align-items: center; justify-content: center;
        transition: all 0.15s ease; flex-shrink: 0;
      }

      .co-radio-input:checked + .co-radio-custom {
        border-color: var(--brand);
        background: var(--brand);
        box-shadow: inset 0 0 0 3px #FFFFFF;
      }

      .co-option-name { font-size: 0.9375rem; font-weight: 600; color: var(--ink); }

      .co-telco-logos, .co-card-logos {
        display: flex; align-items: center; gap: 0.4rem;
      }

      .co-logo-badge {
        width: 28px; height: 28px; border-radius: 50%;
        overflow: hidden; display: flex; align-items: center; justify-content: center;
        box-shadow: 0 1px 2px rgba(0,0,0,0.1);
      }

      .co-option-body {
        padding: 0 1.25rem 1.25rem;
        border-top: 1px solid var(--border);
        padding-top: 1rem;
        display: flex; flex-direction: column; gap: 1rem;
        animation: coFadeIn 0.2s ease-out;
      }

      @keyframes coFadeIn {
        from { opacity: 0; transform: translateY(-4px); }
        to   { opacity: 1; transform: translateY(0); }
      }

      /* ── Coming Soon notice ── */
      .co-coming-soon {
        display: flex; align-items: flex-start; gap: 0.875rem;
        padding: 0.875rem 1rem;
        background: var(--canvas);
        border: 1px solid var(--border-med);
        border-radius: 12px;
        color: var(--muted-text);
      }

      .co-coming-soon svg { flex-shrink: 0; margin-top: 1px; }

      .co-coming-soon-title {
        font-size: 0.875rem; font-weight: 600;
        color: var(--body-text); margin-bottom: 0.2rem;
      }

      .co-coming-soon-desc {
        font-size: 0.8125rem; color: var(--muted-text); line-height: 1.5;
      }

      /* ── Network Tiles ── */
      .co-net-tiles {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 0.5rem;
        margin-top: 0.4rem;
      }

      .co-net-tile {
        display: flex; align-items: center; gap: 0.5rem;
        padding: 0.625rem 0.75rem;
        border: 1.5px solid var(--border-med);
        border-radius: 10px;
        background: var(--canvas);
        cursor: pointer;
        transition: all 0.15s ease;
        text-align: left;
        position: relative;
      }

      .co-net-tile:hover { border-color: var(--border-strong); background: #FFFFFF; }

      .co-net-tile--selected {
        border-color: var(--brand) !important;
        background: #FFFFFF !important;
        box-shadow: 0 2px 8px var(--brand-glow);
      }

      .co-net-logo-wrap {
        width: 22px; height: 22px; border-radius: 50%;
        overflow: hidden; flex-shrink: 0;
        display: flex; align-items: center; justify-content: center;
      }

      .co-net-info { display: flex; flex-direction: column; line-height: 1.15; }
      .co-net-name { font-size: 0.75rem; font-weight: 700; color: var(--ink); }
      .co-net-sub  { font-size: 0.625rem; color: var(--muted-text); }

      .co-net-check { position: absolute; top: 6px; right: 6px; color: var(--brand); }

      /* ── Form controls ── */
      .co-field { display: flex; flex-direction: column; gap: 0.35rem; }

      .co-field-label {
        font-size: 0.8125rem; font-weight: 600; color: var(--body-text);
        display: flex; align-items: center; gap: 0.35rem;
      }

      .co-input {
        width: 100%; padding: 0.75rem 1rem;
        border: 1px solid var(--border-med); border-radius: 12px;
        background: var(--canvas); font-family: inherit;
        font-size: 0.875rem; color: var(--ink);
        transition: all 0.2s ease;
      }

      .co-input:focus {
        outline: none; background: #FFFFFF;
        border-color: var(--brand);
        box-shadow: 0 0 0 4px var(--brand-subtle);
      }

      .co-input--error { border-color: var(--error) !important; background: var(--error-bg) !important; }

      /* Phone Box */
      .co-phone-box {
        display: flex; align-items: center;
        border: 1px solid var(--border-med); border-radius: 12px;
        background: var(--canvas); transition: all 0.2s ease; position: relative;
      }

      .co-phone-box:focus-within {
        border-color: var(--brand); background: #FFFFFF;
        box-shadow: 0 0 0 4px var(--brand-subtle);
      }

      .co-phone-box--error { border-color: var(--error) !important; background: var(--error-bg) !important; }

      .co-flag-pill {
        display: flex; align-items: center; gap: 0.35rem;
        padding: 0.75rem 0.875rem;
        border-right: 1px solid var(--border-med);
        background: #FFFFFF; border-top-left-radius: 12px; border-bottom-left-radius: 12px;
        font-size: 0.8125rem; font-weight: 600; color: var(--ink);
      }

      .co-phone-input { border: none !important; background: transparent !important; box-shadow: none !important; padding-left: 0.75rem; }

      .co-detected-badge {
        margin-right: 0.75rem; font-size: 0.6875rem; font-weight: 700;
        padding: 0.2rem 0.5rem; border-radius: 6px;
        background: var(--brand); color: #FFFFFF;
      }

      .co-detected-badge--mtn      { background: #EAB308; color: #000; }
      .co-detected-badge--telecel  { background: #E60000; color: #fff; }
      .co-detected-badge--at       { background: #1A2B4C; color: #fff; }

      .co-error-text {
        font-size: 0.75rem; color: var(--error); font-weight: 500;
        display: flex; align-items: center; gap: 0.3rem;
      }

      .co-field-hint { font-size: 0.75rem; color: var(--muted-text); line-height: 1.4; }
      .co-field-group { display: flex; flex-direction: column; gap: 0.5rem; }

      /* ── Customer Details ── */
      .co-customer-section {
        border: 1px solid var(--border-med);
        border-radius: 14px;
        overflow: hidden;
        background: var(--canvas);
      }

      .co-customer-heading {
        display: flex; align-items: center; gap: 0.5rem;
        padding: 0.875rem 1.25rem;
        font-size: 0.875rem; font-weight: 700; color: var(--ink);
        border-bottom: 1px solid var(--border);
        background: #FFFFFF;
      }

      .co-customer-heading svg { color: var(--brand); flex-shrink: 0; }

      .co-customer-fields {
        padding: 1rem 1.25rem;
        display: flex; flex-direction: column; gap: 0.875rem;
      }

      /* ── Pay Button ── */
      .co-btn-pay {
        width: 100%; padding: 0.9375rem 1.5rem; border: none; border-radius: 12px;
        background: var(--brand); color: #FFFFFF;
        font-family: 'Plus Jakarta Sans', system-ui, sans-serif;
        font-size: 1rem; font-weight: 700; letter-spacing: -0.01em;
        cursor: pointer; box-shadow: 0 4px 14px var(--brand-glow);
        transition: all 0.15s ease;
        display: flex; align-items: center; justify-content: center;
      }

      .co-btn-pay:hover:not(:disabled) { background: var(--brand-hover); transform: translateY(-1px); box-shadow: 0 6px 20px var(--brand-glow); }
      .co-btn-pay:active:not(:disabled) { transform: translateY(0); }
      .co-btn-pay:disabled { opacity: 0.45; cursor: not-allowed; }

      .co-trust-strip {
        display: flex; align-items: center; justify-content: center; gap: 0.5rem;
        font-size: 0.6875rem; color: var(--muted-text); font-weight: 600;
        text-transform: uppercase; letter-spacing: 0.04em; margin-top: 0.5rem;
      }

      .co-trust-strip span { display: flex; align-items: center; gap: 0.25rem; }

      .co-cancel-wrap { display: flex; justify-content: center; margin-top: 0.75rem; }

      .co-cancel-link {
        display: inline-flex; align-items: center; gap: 0.3rem;
        font-size: 0.75rem; font-weight: 500; color: var(--muted-text);
        text-decoration: none; transition: color 0.15s;
      }

      .co-cancel-link:hover { color: var(--body-text); }

      /* ── Sidebar ── */
      .co-sidebar-column { display: flex; flex-direction: column; gap: 0.75rem; }
      .co-cart-panel { padding: 1.25rem 1.25rem; }
      .co-summary-panel { padding: 1rem 1.25rem; }

      .co-sidebar-title-wrap { display: flex; align-items: center; gap: 0.5rem; color: var(--ink); margin-bottom: 0.875rem; }

      .co-sidebar-title { font-size: 0.9375rem; font-weight: 700; letter-spacing: -0.01em; }

      .co-cart-items-list { display: flex; flex-direction: column; gap: 0.875rem; }

      .co-cart-item {
        display: flex; align-items: center; gap: 0.875rem;
        padding-bottom: 0.875rem; border-bottom: 1px solid var(--border);
      }

      .co-cart-item:last-child { padding-bottom: 0; border-bottom: none; }

      .co-thumb-box {
        width: 44px; height: 44px; flex-shrink: 0;
        border-radius: 10px; border: 1px solid var(--border-med);
        background: var(--canvas); display: flex; align-items: center; justify-content: center;
        color: var(--subtle-text);
      }

      .co-thumb-img {
        width: 44px; height: 44px; flex-shrink: 0;
        border-radius: 10px; object-fit: cover;
        border: 1px solid var(--border-med);
      }

      .co-item-details { flex: 1; display: flex; flex-direction: column; gap: 0.3rem; }

      .co-item-top { display: flex; align-items: flex-start; justify-content: space-between; }

      .co-item-title { font-size: 0.8125rem; font-weight: 600; color: var(--ink); line-height: 1.3; }

      .co-item-bottom { display: flex; align-items: center; justify-content: space-between; }

      .co-item-qty { font-size: 0.75rem; color: var(--muted-text); }
      .co-item-price { font-size: 0.875rem; font-weight: 700; color: var(--ink); }

      /* ── Summary ── */
      .co-summary-rows { display: flex; flex-direction: column; gap: 0.625rem; }

      .co-summary-row { display: flex; justify-content: space-between; font-size: 0.8125rem; }

      .co-summary-label { color: var(--prose-text); }
      .co-summary-val   { font-weight: 600; color: var(--ink); }

      .co-summary-row--discount .co-summary-label,
      .co-summary-row--discount .co-summary-val { color: var(--success); font-weight: 700; }

      .co-summary-divider { height: 1px; background: var(--border-med); margin: 0.35rem 0; }

      .co-summary-row--total { align-items: center; margin-top: 0.25rem; }

      .co-total-label { font-size: 1rem; font-weight: 800; color: var(--ink); }

      .co-total-val {
        font-family: 'Plus Jakarta Sans', system-ui, sans-serif;
        font-size: 1.375rem; font-weight: 800; color: var(--ink); letter-spacing: -0.02em;
      }

      /* ── Terminal states ── */
      .co-terminal-panel {
        max-width: 520px; margin: 2rem auto; padding: 2.5rem 2rem;
        text-align: center; display: flex; flex-direction: column;
        align-items: center; gap: 1rem;
      }

      .co-terminal-title { font-size: 1.375rem; font-weight: 800; color: var(--ink); }

      .co-terminal-desc { font-size: 0.875rem; color: var(--body-text); line-height: 1.6; max-width: 340px; }

      .co-terminal-amount {
        font-family: 'Plus Jakarta Sans', sans-serif;
        font-size: 2.25rem; font-weight: 800; color: var(--brand);
      }

      .co-success-icon-wrap {
        width: 64px; height: 64px; border-radius: 50%;
        background: var(--success-bg);
        display: flex; align-items: center; justify-content: center;
      }

      .co-warn-icon-wrap {
        width: 56px; height: 56px; border-radius: 50%;
        background: #FEF3C7;
        display: flex; align-items: center; justify-content: center;
      }

      .co-receipt-box {
        width: 100%; background: var(--canvas);
        border: 1px solid var(--border-med); border-radius: 12px;
        padding: 1rem; display: flex; flex-direction: column; gap: 0.5rem;
        font-size: 0.8125rem; margin: 0.5rem 0;
      }

      .co-receipt-row { display: flex; justify-content: space-between; }
      .co-receipt-mono { font-family: monospace; font-size: 0.75rem; color: var(--muted-text); }

      .co-badge-paid {
        background: var(--success); color: #FFFFFF;
        font-size: 0.6875rem; font-weight: 700;
        padding: 0.2rem 0.5rem; border-radius: 999px;
      }

      .co-btn-primary {
        display: inline-flex; align-items: center; justify-content: center;
        background: var(--brand); color: #FFFFFF;
        padding: 0.875rem 1.75rem; border-radius: 10px;
        text-decoration: none; font-weight: 700; font-size: 0.9375rem;
        transition: opacity 0.15s;
      }

      .co-btn-primary:hover { opacity: 0.88; }

      /* ── Spinner ── */
      .co-spinner { width: 48px; height: 48px; position: relative; }

      .co-spinner-ring {
        width: 100%; height: 100%; border-radius: 50%;
        border: 4px solid var(--brand-subtle);
        border-top-color: var(--brand);
        animation: coSpin 0.8s linear infinite;
      }

      @keyframes coSpin { to { transform: rotate(360deg); } }

      .co-progress-bar {
        width: 100%; height: 6px; background: var(--border-med);
        border-radius: 999px; overflow: hidden;
      }

      .co-progress-fill {
        height: 100%; background: var(--brand); border-radius: 999px;
        animation: coPulse 2s ease-in-out infinite alternate;
      }

      @keyframes coPulse { from { width: 30%; } to { width: 90%; } }

      .co-terminal-hint { font-size: 0.75rem; color: var(--muted-text); }

      /* ── Footer ── */
      .co-page-footer {
        text-align: center; font-size: 0.75rem;
        color: var(--muted-text); padding: 1rem 0;
      }
    </style>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp init_from_session(socket, session) do
    now_unix = System.os_time(:second)
    expires = parse_expires(session["expires_at"])
    page_state = resolve_state(session["state"], expires, now_unix)
    methods = parse_methods(session["checkout_layout"])
    line_items = session["line_items"] || []

    socket
    |> base_assigns(page_state)
    |> assign(
      session: session,
      session_public_id: session["public_id"],
      success_url: session["success_url"],
      currency: session["currency"] || "GHS",
      line_items: line_items,
      total_amount: session["total_amount"] || 0,
      subtotal_amount: session["subtotal_amount"] || session["total_amount"] || 0,
      tax_amount: session["tax_amount"] || 0,
      shipping_amount: session["shipping_amount"] || 0,
      discount_amount: session["discount_amount"] || 0,
      methods: methods,
      selected_method: hd(methods)["id"],
      cancel_url: session["cancel_url"],
      collect_email: session["collect_email"] == true,
      collect_phone: session["collect_phone"] == true,
      collect_name: session["collect_name"] == true,
      logo_url: (session["checkout_layout"] || %{})["logo_url"]
    )
    |> maybe_start_poll(page_state)
  end

  defp parse_methods(nil), do: default_methods()

  defp parse_methods(%{"methods" => methods}) when is_list(methods) and methods != [] do
    visible =
      methods
      |> Enum.filter(& &1["visible"] != false)
      |> Enum.filter(& &1["id"] in ~w[mobile_money card bank_transfer])

    if visible == [], do: default_methods(), else: visible
  end

  defp parse_methods(_), do: default_methods()

  defp default_methods do
    [
      %{"id" => "mobile_money",  "label" => "Mobile Money"},
      %{"id" => "card",          "label" => "Credit / Debit Card"},
      %{"id" => "bank_transfer", "label" => "Bank Transfer"}
    ]
  end

  defp method_enabled?(methods, id), do: Enum.any?(methods, & &1["id"] == id)

  defp base_assigns(socket, page_state) do
    assign(socket,
      page_state: page_state,
      session: nil,
      session_public_id: nil,
      payment_public_id: nil,
      success_url: nil,
      networks: @networks,
      methods: default_methods(),
      selected_method: "mobile_money",
      selected_network: nil,
      phone: "",
      phone_error: nil,
      error: nil,
      detected_network: nil,
      currency: "GHS",
      line_items: [],
      total_amount: 0,
      subtotal_amount: 0,
      tax_amount: 0,
      shipping_amount: 0,
      discount_amount: 0,
      poll_count: 0,
      cancel_url: nil,
      collect_email: false,
      collect_phone: false,
      collect_name: false,
      customer_email: "",
      customer_phone: "",
      customer_name: "",
      collection_errors: %{},
      logo_url: nil
    )
  end

  defp resolve_state("completed", _e, _n), do: :done
  defp resolve_state("cancelled", _e, _n), do: :cancelled
  defp resolve_state("expired",   _e, _n), do: :expired
  defp resolve_state(_s, expires, now) when is_integer(expires) and expires < now, do: :expired
  defp resolve_state("processing", _e, _n), do: :processing
  defp resolve_state(_s, _e, _n), do: :form

  defp maybe_start_poll(socket, :processing) do
    if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)
    socket
  end

  defp maybe_start_poll(socket, _), do: socket

  defp submit_payment(socket, phone) do
    %{assigns: %{
      session_public_id: sid,
      selected_network: sel_net,
      customer_email: email,
      customer_phone: customer_phone,
      customer_name: name
    }} = socket
    network = sel_net || detect_network(phone)

    attrs =
      %{method: "mobile_money", msisdn: phone, network: network}
      |> then(fn a -> if email != "", do: Map.put(a, :customer_email, email), else: a end)
      |> then(fn a -> if customer_phone != "", do: Map.put(a, :customer_phone, customer_phone), else: a end)
      |> then(fn a -> if name != "", do: Map.put(a, :customer_name, name), else: a end)

    case CoreClient.pay_session(sid, attrs) do
      {:ok, %{"payment_public_id" => pay_id}} ->
        if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)

        {:noreply,
         assign(socket,
           page_state: :processing,
           payment_public_id: pay_id,
           poll_count: 0,
           error: nil,
           phone_error: nil
         )}

      {:error, _} ->
        {:noreply,
         assign(socket,
           error: "We couldn't process your payment. Please verify your mobile number and balance."
         )}
    end
  end

  defp finalize(socket, session_id, pay_id) do
    socket = push_event(socket, "confetti", %{})

    case CoreClient.complete_session(session_id, pay_id) do
      {:ok, %{"success_url" => url}} when is_binary(url) and url != "" ->
        if connected?(socket) and external_url?(url) do
          Process.send_after(self(), {:auto_redirect, url}, 3_500)
        end
        {:noreply, assign(socket, page_state: :done, success_url: url)}

      _ ->
        {:noreply, assign(socket, page_state: :done)}
    end
  end

  defp external_url?(url) do
    not String.contains?(url, "localhost") and not String.contains?(url, "pay.yagye.com")
  end

  defp validate_collection(params, assigns) do
    errors = %{}

    errors =
      if assigns.collect_name and String.trim(params["customer_name"] || "") == "",
        do: Map.put(errors, "name", "Full name is required"),
        else: errors

    errors =
      if assigns.collect_email do
        email = String.trim(params["customer_email"] || "")
        cond do
          email == "" -> Map.put(errors, "email", "Email address is required")
          not Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email) -> Map.put(errors, "email", "Please enter a valid email address")
          true -> errors
        end
      else
        errors
      end

    errors =
      if assigns.collect_phone and String.trim(params["customer_phone"] || "") == "",
        do: Map.put(errors, "phone", "Phone number is required"),
        else: errors

    errors
  end

  defp validate_phone(phone, selected_network) do
    stripped = String.replace(phone, ~r/\D/, "")
    prefix = String.slice(stripped, 0, 3)
    detected = detect_network(stripped)

    cond do
      String.length(stripped) != 10 ->
        {:error, "Ghana phone numbers must be exactly 10 digits (e.g. 024 123 4567)"}

      not String.starts_with?(stripped, "0") ->
        {:error, "Phone number must start with 0 (e.g. 024 123 4567)"}

      is_nil(detected) ->
        {:error, "Unrecognised Ghana mobile prefix (#{prefix})"}

      not is_nil(selected_network) and detected != selected_network ->
        {:error, "#{stripped} belongs to #{detected}, but you selected #{selected_network}"}

      true ->
        :ok
    end
  end

  defp detect_network(phone) do
    prefix = String.slice(phone, 0, 3)

    cond do
      prefix in @mtn_prefixes -> "MTN"
      prefix in @telecel_prefixes -> "Telecel"
      prefix in @airteltigo_prefixes -> "AirtelTigo"
      true -> nil
    end
  end

  defp parse_expires(nil), do: nil

  defp parse_expires(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> nil
    end
  end

  defp parse_expires(_), do: nil

  defp format_amount_parts(amount) when is_integer(amount) do
    whole = div(abs(amount), 100) |> Integer.to_string()
    cents = rem(abs(amount), 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    {whole, cents}
  end

  defp format_amount_parts(_), do: {"0", "00"}

  defp currency_symbol("GHS"), do: "GH₵"
  defp currency_symbol("NGN"), do: "₦"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("GBP"), do: "£"
  defp currency_symbol(_),     do: "GH₵"

  defp network_label("MTN"),        do: "MTN MoMo"
  defp network_label("Telecel"),    do: "Telecel Cash"
  defp network_label("AirtelTigo"), do: "AT Money"
  defp network_label(n),            do: n || "Mobile Money"

  defp network_prefix_hint("MTN"),        do: "024 · 054 · 055"
  defp network_prefix_hint("Telecel"),    do: "020 · 050"
  defp network_prefix_hint("AirtelTigo"), do: "026 · 056 · 027"
  defp network_prefix_hint(_),            do: ""

  defp network_css_key("MTN"),        do: "mtn"
  defp network_css_key("Telecel"),    do: "telecel"
  defp network_css_key("AirtelTigo"), do: "at"
  defp network_css_key(_),            do: "mtn"

  defp method_label("mobile_money"),  do: "Mobile Money"
  defp method_label("card"),          do: "Credit / Debit Card"
  defp method_label("bank_transfer"), do: "Bank Transfer"
  defp method_label(m),               do: m

  defp merchant_brand_name(%{"metadata" => %{"merchant_name" => name}})
       when is_binary(name) and name != "",
       do: name

  defp merchant_brand_name(_), do: "Yagye"

  defp network_svg("MTN") do
    ~s(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="16" fill="#FFCC00"/><path d="M7 16c0-4.97 4.03-9 9-9s9 4.03 9 9-4.03 9-9 9-9-4.03-9-9z" fill="#002B49"/><path d="M12 19.5v-7l3 4.5 3-4.5v7" stroke="#FFCC00" stroke-width="2" stroke-linecap="round"/></svg>)
  end

  defp network_svg("Telecel") do
    ~s(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><circle cx="16" cy="16" r="16" fill="#E60000"/><circle cx="16" cy="16" r="10" stroke="#FFF" stroke-width="2.5" fill="none"/><path d="M16 11v10M12 15h8" stroke="#FFF" stroke-width="2.5" stroke-linecap="round"/></svg>)
  end

  defp network_svg("AirtelTigo") do
    ~s(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><circle cx="16" cy="16" r="16" fill="#1A2B4C"/><path d="M0 16a16 16 0 0 0 32 0H0z" fill="#ED1C24"/><text x="16" y="19" font-family="Inter,sans-serif" font-size="12" font-weight="900" fill="#FFF" text-anchor="middle">at</text></svg>)
  end

  defp network_svg(_), do: ~s(<svg width="22" height="22" viewBox="0 0 32 32" fill="none"><circle cx="16" cy="16" r="16" fill="#E5E7EB"/></svg>)

  # ── Card SVGs ──────────────────────────────────────────────────────────────

  defp card_brand_svg("visa") do
    ~s(<svg width="34" height="22" viewBox="0 0 40 26" xmlns="http://www.w3.org/2000/svg"><rect width="40" height="26" rx="4" fill="#1A1F71"/><text x="20" y="18" font-family="Inter,sans-serif" font-size="11" font-weight="900" fill="#FFF" text-anchor="middle" letter-spacing="1">VISA</text></svg>)
  end

  defp card_brand_svg("mastercard") do
    ~s(<svg width="34" height="22" viewBox="0 0 40 26" xmlns="http://www.w3.org/2000/svg"><rect width="40" height="26" rx="4" fill="#1D1D1B"/><circle cx="15" cy="13" r="7.5" fill="#EB001B"/><circle cx="25" cy="13" r="7.5" fill="#F79E1B"/><path d="M20 7.8a7.5 7.5 0 010 10.4A7.5 7.5 0 0120 7.8z" fill="#FF5F00"/></svg>)
  end

  defp card_brand_svg("verve") do
    ~s(<svg width="34" height="22" viewBox="0 0 40 26" xmlns="http://www.w3.org/2000/svg"><rect width="40" height="26" rx="4" fill="#E31837"/><text x="20" y="17" font-family="Inter,sans-serif" font-size="10" font-weight="700" fill="#FFF" text-anchor="middle">verve</text></svg>)
  end

  defp card_brand_svg(_) do
    ~s(<svg width="34" height="22" viewBox="0 0 40 26" xmlns="http://www.w3.org/2000/svg"><rect width="40" height="26" rx="4" fill="#F3F4F6"/><rect x="5" y="9" width="30" height="8" rx="2" fill="#E5E7EB"/></svg>)
  end
end
