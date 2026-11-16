defmodule YagyeCheckoutWeb.Live.CheckoutLive do
  use Phoenix.LiveView, layout: false
  import Phoenix.HTML, only: [raw: 1]

  require Logger

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
    ua_hash = capture_ua_hash(socket)

    case CoreClient.get_session(token) do
      {:ok, session} -> {:ok, init_from_session(socket, session) |> assign(user_agent_hash: ua_hash)}
      {:error, :not_found} -> {:ok, base_assigns(socket, :not_found)}
      {:error, _} -> {:ok, base_assigns(socket, :error)}
    end
  end

  # ── Event Handlers ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_method", %{"method" => method}, socket)
      when method == socket.assigns.selected_method do
    {:noreply, socket}
  end

  def handle_event("select_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, selected_method: method, error: nil, phone_error: nil)}
  end

  def handle_event("change_customer_name", %{"customer_name" => val}, socket) do
    {:noreply, assign(socket, customer_name: val)}
  end

  def handle_event("change_customer_email", %{"customer_email" => val}, socket) do
    {:noreply, assign(socket, customer_email: val)}
  end

  def handle_event("change_customer_phone", %{"customer_phone" => val}, socket) do
    {:noreply, assign(socket, customer_phone: val)}
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

  def handle_event("change_card_number", %{"card_number" => val}, socket) do
    digits = String.replace(val, ~r/\D/, "") |> String.slice(0, 16)
    formatted = digits |> String.graphemes() |> Enum.chunk_every(4) |> Enum.map(&Enum.join/1) |> Enum.join(" ")
    {:noreply, assign(socket, card_number: formatted, card_brand: detect_card_brand(digits), card_errors: Map.delete(socket.assigns.card_errors, "number"), error: nil)}
  end

  def handle_event("change_card_expiry", %{"card_expiry" => val}, socket) do
    digits = String.replace(val, ~r/\D/, "") |> String.slice(0, 4)
    formatted = if String.length(digits) > 2, do: String.slice(digits, 0, 2) <> "/" <> String.slice(digits, 2, 2), else: digits
    {:noreply, assign(socket, card_expiry: formatted, card_errors: Map.delete(socket.assigns.card_errors, "expiry"), error: nil)}
  end

  def handle_event("change_card_cvv", %{"card_cvv" => val}, socket) do
    {:noreply, assign(socket, card_cvv: String.replace(val, ~r/\D/, "") |> String.slice(0, 4), card_errors: Map.delete(socket.assigns.card_errors, "cvv"), error: nil)}
  end

  def handle_event("change_card_name", %{"card_name" => val}, socket) do
    {:noreply, assign(socket, card_name: val, card_errors: Map.delete(socket.assigns.card_errors, "name"), error: nil)}
  end

  def handle_event("simulate_transfer", _params, %{assigns: %{simulation_mode: true, payment_public_id: pay_id}} = socket) do
    case CoreClient.simulate_bank_transfer(pay_id) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, assign(socket, error: "Simulation failed — check that the simulator server is running.")}
    end
  end

  def handle_event("simulate_transfer", _params, socket), do: {:noreply, socket}

  # ── Escrow events ─────────────────────────────────────────────────────────────

  def handle_event("escrow_show_confirm_modal", _params, socket) do
    {:noreply, assign(socket, escrow_confirm_modal: true)}
  end

  def handle_event("escrow_hide_confirm_modal", _params, socket) do
    {:noreply, assign(socket, escrow_confirm_modal: false)}
  end

  def handle_event("escrow_change_note", %{"dispute_note" => note}, socket) do
    {:noreply, assign(socket, dispute_note: note)}
  end

  def handle_event("escrow_confirm_receipt", _params, %{assigns: %{escrow_hold: hold}} = socket) do
    socket = assign(socket, escrow_confirming: true, escrow_confirm_modal: false)
    hold_id = hold && hold["public_id"]

    case CoreClient.confirm_escrow_receipt(hold_id) do
      {:ok, _} ->
        {:noreply, assign(socket, page_state: :done, escrow_confirming: false)}

      {:error, _} ->
        {:noreply, assign(socket, escrow_confirming: false, error: "Could not confirm receipt. Please try again or contact support.")}
    end
  end

  def handle_event("escrow_open_dispute", _params, %{assigns: %{escrow_hold: hold, dispute_note: note}} = socket) do
    socket = assign(socket, escrow_disputing: true)
    hold_id = hold && hold["public_id"]

    case CoreClient.open_escrow_dispute(hold_id, note) do
      {:ok, _} ->
        {:noreply, assign(socket, page_state: :escrow_disputed, escrow_disputing: false)}

      {:error, _} ->
        {:noreply, assign(socket, escrow_disputing: false, error: "Could not open dispute. Please try again or contact support.")}
    end
  end

  def handle_event("toggle_terms", _params, socket) do
    {:noreply, assign(socket, terms_accepted: !socket.assigns.terms_accepted, terms_error: nil)}
  end

  # Stripe.js payment method created successfully — proceed with card payment.
  def handle_event("stripe_pm_ready", %{"payment_method_id" => pm_id}, socket) do
    submit_card_stripe(socket, pm_id)
  end

  # Stripe.js tokenization error — show error message and re-enable the form.
  def handle_event("stripe_error", %{"message" => msg}, socket) do
    {:noreply, assign(socket, submitting: false, stripe_card_error: msg)}
  end

  # Guard: ignore submit while a payment request is already in-flight.
  def handle_event("submit_checkout", _params, %{assigns: %{submitting: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("submit_checkout", params, socket) do
    if socket.assigns.terms_enabled and not socket.assigns.terms_accepted do
      {:noreply, assign(socket, terms_error: "You must accept the terms to continue")}
    else
      collection_errors = validate_collection(params, socket.assigns)

      if collection_errors != %{} do
        {:noreply, assign(socket, collection_errors: collection_errors)}
      else
        token = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

        socket =
          assign(socket,
            submitting: true,
            submission_token: token,
            customer_email: String.trim(params["customer_email"] || ""),
            customer_phone: String.trim(params["customer_phone"] || ""),
            customer_name: String.trim(params["customer_name"] || ""),
            collection_errors: %{}
          )

        case socket.assigns.selected_method do
          "mobile_money" ->
            phone =
              Map.get(params, "phone", socket.assigns.phone)
              |> to_string()
              |> String.replace(~r/[\s\-()]/, "")

            case validate_phone(phone, socket.assigns.selected_network) do
              {:error, msg} -> {:noreply, assign(socket, submitting: false, phone_error: msg)}
              :ok -> submit_mobile_money(socket, phone)
            end

          "card" when socket.assigns.card_psp == "stripe" ->
            # Stripe.js handles card entry — push event to hook to trigger tokenization.
            # The hook will call back with stripe_pm_ready or stripe_error.
            {:noreply,
             socket
             |> assign(stripe_card_error: nil)
             |> push_event("stripe_tokenize", %{})}

          "card" ->
            cn_raw = params["card_number"] || socket.assigns.card_number
            cn_digits = String.replace(cn_raw, ~r/\D/, "") |> String.slice(0, 16)
            cn_formatted = cn_digits |> String.graphemes() |> Enum.chunk_every(4) |> Enum.map(&Enum.join/1) |> Enum.join(" ")
            exp_raw = params["card_expiry"] || socket.assigns.card_expiry
            exp_digits = String.replace(exp_raw, ~r/\D/, "") |> String.slice(0, 4)
            exp_formatted = if String.length(exp_digits) > 2, do: String.slice(exp_digits, 0, 2) <> "/" <> String.slice(exp_digits, 2, 2), else: exp_digits
            socket =
              assign(socket,
                card_number: cn_formatted,
                card_brand: detect_card_brand(cn_digits),
                card_expiry: exp_formatted,
                card_cvv: String.replace(params["card_cvv"] || socket.assigns.card_cvv, ~r/\D/, "") |> String.slice(0, 4),
                card_name: params["card_name"] || socket.assigns.card_name
              )
            errs = validate_card(socket.assigns.card_number, socket.assigns.card_expiry, socket.assigns.card_cvv, socket.assigns.card_name)
            if errs != %{}, do: {:noreply, assign(socket, submitting: false, card_errors: errs)}, else: submit_card(socket)

          "bank_transfer" ->
            submit_bank_transfer(socket)

          _ ->
            {:noreply, assign(socket, submitting: false)}
        end
      end
    end
  end

  def handle_info({:auto_redirect, url}, socket) do
    {:noreply, push_event(socket, "redirect_to", %{url: url})}
  end

  def handle_info(:tick_countdown, socket) do
    if connected?(socket) and socket.assigns.page_state == :awaiting_transfer do
      Process.send_after(self(), :tick_countdown, 1_000)
    end

    {:noreply, assign(socket, now_unix: System.os_time(:second))}
  end

  # Bank transfer: no max-poll cutoff — PaymentTimeoutWorker on core handles the 30-min expiry.
  @impl true
  def handle_info(:poll, %{assigns: %{page_state: :awaiting_transfer, payment_public_id: pay_id, session_public_id: sid, poll_count: n}} = socket) do
    result = CoreClient.get_payment_state(pay_id)
    Logger.info("[checkout] bank_transfer poll pay_id=#{pay_id} poll_count=#{n} result=#{inspect(result)}")

    case result do
      {:ok, %{"state" => "succeeded"}} ->
        finalize(socket, sid, pay_id)

      {:ok, %{"state" => "escrow_held"}} ->
        finalize_escrow(socket, pay_id)

      {:ok, %{"state" => state}} when state in ["failed", "cancelled", "expired"] ->
        {:noreply,
         assign(socket,
           page_state: :form,
           virtual_account: nil,
           va_expires_unix: nil,
           error: "Bank transfer timed out or was not completed. Please try again."
         )}

      {:ok, %{"state" => "requires_action"} = resp} ->
        va = resp["virtual_account"]

        socket =
          if is_map(va) and is_nil(socket.assigns.virtual_account) do
            expires_unix = parse_va_expires(va["expires_at"])
            if connected?(socket), do: Process.send_after(self(), :tick_countdown, 1_000)
            assign(socket, virtual_account: va, va_expires_unix: expires_unix)
          else
            socket
          end

        Process.send_after(self(), :poll, @poll_ms)
        {:noreply, assign(socket, poll_count: n + 1)}

      _ ->
        Process.send_after(self(), :poll, @poll_ms)
        {:noreply, assign(socket, poll_count: n + 1)}
    end
  end

  # Mobile money / card: stop after @max_polls (~2 min).
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

      {:ok, %{"state" => "escrow_held"}} ->
        finalize_escrow(socket, pay_id)

      {:ok, %{"state" => "cancelled"}} ->
        {:noreply, assign(socket, page_state: :form, error: "Payment was not completed. Please try again when you're ready.")}

      {:ok, %{"state" => "failed"}} ->
        {:noreply, assign(socket, page_state: :form, error: "Payment was declined. Please check your balance and try again.")}

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
              <%= case @processing_method do %>
                <% "card" -> %>
                  Verifying your card. This takes just a moment.
                <% "bank_transfer" -> %>
                  Confirming your transfer. We're checking for your payment now.
                <% _ -> %>
                  A USSD prompt was sent to <strong>{@phone}</strong>. Open it and enter your PIN to approve the payment.
              <% end %>
            </p>
            <div class="co-progress-bar"><div class="co-progress-fill"></div></div>
            <p class="co-terminal-hint">This page updates automatically once your payment is confirmed.</p>
          </div>

        <% :awaiting_transfer -> %>
          <div class="co-panel co-terminal-panel co-terminal-panel--await">
            <%= if @virtual_account do %>
              <div class="co-await-status">
                <span class="co-live-dot"></span>
                <span>Waiting for your transfer</span>
              </div>
              <p class="co-terminal-desc">
                Transfer <strong>exactly</strong>
                <% {bw, bc} = format_amount_parts(@total_amount) %>
                <strong>{currency_symbol(@currency)}{bw}.{bc}</strong>
                to the account below — your payment is confirmed automatically.
              </p>

              <div class="co-va-panel">
                <div class="co-va-row">
                  <span class="co-va-label">Bank</span>
                  <span class="co-va-value">{@virtual_account["bank_name"] || "Partner Bank"}</span>
                </div>
                <div class="co-va-row">
                  <span class="co-va-label">Account name</span>
                  <span class="co-va-value">{@virtual_account["account_name"] || "YAGYE COLLECT"}</span>
                </div>
                <div class="co-va-row co-va-row--accent">
                  <span class="co-va-label">Account number</span>
                  <div class="co-va-account-wrap">
                    <span class="co-mono co-va-number">
                      {format_account_number(@virtual_account["account_number"])}
                    </span>
                    <button
                      type="button"
                      class="co-copy-btn"
                      onclick={"navigator.clipboard.writeText('#{@virtual_account["account_number"]}').then(()=>{this.textContent='Copied!';setTimeout(()=>this.textContent='Copy',2000)})"}
                    >Copy</button>
                  </div>
                </div>
                <div class="co-va-row co-va-row--amount">
                  <span class="co-va-label">Amount to send</span>
                  <span class="co-va-amount">{currency_symbol(@currency)}{bw}.{bc}</span>
                </div>
              </div>

              <div class="co-va-warn">
                <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;margin-top:1px">
                  <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
                </svg>
                Send <strong>exactly</strong> this amount — any difference will cause the transfer to be rejected.
              </div>

              <div class="co-va-meta">
                <div class="co-va-expiry">
                  <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
                  </svg>
                  Account expires in
                  <strong class={"co-countdown#{if countdown_urgent?(@va_expires_unix, @now_unix), do: " co-countdown--urgent"}"}>{format_countdown(@va_expires_unix, @now_unix)}</strong>
                </div>
                <div class="co-va-rail">
                  <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="13 17 18 12 13 7"/><polyline points="6 17 11 12 6 7"/>
                  </svg>
                  Use <strong>{if @bank_transfer_psp == "paystack", do: "Paystack bank transfer", else: "GhIPSS Instant Pay"}</strong> — usually under 30 seconds
                </div>
              </div>

              <%= if @simulation_mode do %>
                <button type="button" class="co-simulate-transfer-btn" phx-click="simulate_transfer">
                  ⚡ Simulate Transfer
                </button>
              <% end %>

              <p class="co-terminal-hint">Do not close this page — it updates automatically when we receive your transfer.</p>

            <% else %>
              <div class="co-spinner"><div class="co-spinner-ring"></div></div>
              <h2 class="co-terminal-title">Generating transfer account…</h2>
              <p class="co-terminal-desc">Preparing a dedicated bank account for this payment.</p>
            <% end %>
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

        <% :escrow_held -> %>
          <% {whole, cents} = format_amount_parts(@total_amount) %>
          <div class="co-panel co-terminal-panel co-escrow-panel">
            <div class="co-escrow-icon-wrap">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#d97706" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
              </svg>
            </div>
            <h2 class="co-terminal-title">Payment Held in Trust</h2>
            <div class="co-terminal-amount">{currency_symbol(@currency)}{whole}.{cents}</div>
            <p class="co-terminal-desc">
              Your payment is safely held. Once you confirm you've received your order, the merchant will be paid. If something is wrong, open a dispute below.
            </p>
            <div class="co-escrow-notice">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;margin-top:1px"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
              Funds release automatically in {@escrow_hold && @escrow_hold["auto_release_days"] || 7} days if you take no action.
            </div>
            <%= if @error do %>
              <div class="co-error-banner">{@error}</div>
            <% end %>
            <button class="co-btn-primary co-escrow-confirm-btn" phx-click="escrow_show_confirm_modal" disabled={@escrow_confirming}>
              <%= if @escrow_confirming do %>Confirming…<% else %>I've received my order ✓<% end %>
            </button>
            <div class="co-escrow-divider">or</div>
            <div class="co-escrow-dispute-section">
              <p class="co-escrow-dispute-label">Something went wrong with your order?</p>
              <textarea
                phx-change="escrow_change_note"
                name="dispute_note"
                placeholder="Describe the issue — e.g. item not received, wrong item..."
                class="co-escrow-dispute-note"
                rows="3"
              >{@dispute_note}</textarea>
              <button class="co-btn-secondary" phx-click="escrow_open_dispute" phx-disable-with="Opening dispute…" disabled={@escrow_disputing || String.trim(@dispute_note) == ""}>
                Open a dispute
              </button>
            </div>
            <div class="co-receipt-box" style="margin-top:16px">
              <div class="co-receipt-row">
                <span>Reference</span>
                <span class="co-receipt-mono">{@session && @session["public_id"]}</span>
              </div>
              <div class="co-receipt-row">
                <span>Status</span>
                <span class="co-badge-escrow">Held in Trust</span>
              </div>
            </div>
            <%= if @escrow_confirm_modal do %>
              <div class="co-modal-overlay" phx-click="escrow_hide_confirm_modal">
                <div class="co-modal" phx-click-stop="">
                  <h3 class="co-modal-title">Confirm receipt?</h3>
                  <p class="co-modal-body">
                    This is irreversible — once confirmed, the merchant will receive the funds immediately. Only confirm if you have fully received your order.
                  </p>
                  <div class="co-modal-actions">
                    <button class="co-btn-ghost" phx-click="escrow_hide_confirm_modal">Cancel</button>
                    <button class="co-btn-primary" phx-click="escrow_confirm_receipt" phx-disable-with="Confirming…">Yes, confirm receipt</button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

        <% :escrow_disputed -> %>
          <div class="co-panel co-terminal-panel co-terminal-panel--info">
            <div class="co-escrow-icon-wrap co-escrow-icon-wrap--disputed">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#3b82f6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
              </svg>
            </div>
            <h2 class="co-terminal-title">Dispute Opened</h2>
            <p class="co-terminal-desc">
              Your dispute has been received. Our team will review it within 2 business days and notify you of the outcome.
            </p>
            <div class="co-receipt-box">
              <div class="co-receipt-row">
                <span>Reference</span>
                <span class="co-receipt-mono">{@session && @session["public_id"]}</span>
              </div>
              <div class="co-receipt-row">
                <span>Status</span>
                <span class="co-badge-pending">Under Review</span>
              </div>
            </div>
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
          <%!-- ── Split Layout: Summary left, Form right ── --%>
          <div class="co-split">

            <%!-- ══ LEFT PANEL: Order Summary ══ --%>
            <div class="co-panel-left">

              <%!-- Breadcrumb --%>
              <nav class="co-breadcrumb">
                <%= if @cancel_url && external_url?(@cancel_url) do %>
                  <a href={@cancel_url} class="co-bc-close" aria-label="Close">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                  </a>
                  <span class="co-bc-sep">|</span>
                <% end %>
                <span class="co-bc-active">Checkout</span>
                <%= if @checkout_mode != "live" do %>
                  <span class={"co-mode-badge co-mode-badge--#{@checkout_mode}"}>{String.capitalize(@checkout_mode)}</span>
                <% end %>
              </nav>

              <%!-- Merchant row --%>
              <div class="co-merchant-row">
                <%= if @logo_url && @logo_url != "" do %>
                  <img src={@logo_url} alt="Merchant" class="co-merchant-logo-img" />
                <% else %>
                  <div class="co-merchant-icon-box">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                      <path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/>
                    </svg>
                  </div>
                <% end %>
                <div>
                  <div class="co-merchant-name-label">{@checkout_business_name || merchant_brand_name(@session)}</div>
                  <div class="co-merchant-verified">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                    </svg>
                    Verified merchant
                  </div>
                </div>
              </div>

              <%!-- Amount hero --%>
              <% {hero_w, hero_c} = format_amount_parts(@total_amount) %>
              <div class="co-amount-hero">
                <div class="co-amount-hero-label">Pay</div>
                <div class="co-amount-hero-val">{currency_symbol(@currency)}{hero_w}.{hero_c}</div>
              </div>

              <%!-- Order summary --%>
              <%= if @line_items == [] do %>
                <div class="co-section-label">Order summary</div>
                <% {orig_w, orig_c} = format_amount_parts(@subtotal_amount) %>
                <div class="co-item-card">
                  <div class="co-item-body">
                    <div class="co-item-name">{@session && (@session["description"] || "Payment")}</div>
                    <div class="co-item-bottom">
                      <span class="co-item-qty">1 payment</span>
                      <%= if @discount_amount > 0 do %>
                        <span class="co-item-price" style="text-decoration:line-through;color:var(--muted-text);font-weight:400;">{currency_symbol(@currency)}{orig_w}.{orig_c}</span>
                      <% else %>
                        <span class="co-item-price">{currency_symbol(@currency)}{hero_w}.{hero_c}</span>
                      <% end %>
                    </div>
                  </div>
                </div>
                <div class="co-totals-block">
                  <%= if @discount_amount > 0 do %>
                    <div class="co-total-row"><span>Subtotal</span><span>{currency_symbol(@currency)}{orig_w}.{orig_c}</span></div>
                    <% {dc_w, dc_c} = format_amount_parts(@discount_amount) %>
                    <div class="co-total-row co-total-row--discount">
                      <span class="co-disc-label">
                        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color:var(--success)"><polyline points="20.59 13.41 13.42 20.58 6.37 13.53 13.53 6.37 20.59 13.41"/><line x1="6" y1="6" x2="6.01" y2="6"/></svg>
                        Discount
                      </span>
                      <span>−{currency_symbol(@currency)}{dc_w}.{dc_c}</span>
                    </div>
                  <% end %>
                  <div class="co-grand-row">
                    <span class="co-grand-label">Total due</span>
                    <span class="co-grand-val">{currency_symbol(@currency)}{hero_w}.{hero_c}</span>
                  </div>
                </div>
              <% else %>
                <% item_line_items = Enum.filter(@line_items, &(&1["kind"] == "item" or is_nil(&1["kind"]))) %>
                <% first_discount = Enum.find(@line_items, &(&1["kind"] == "discount")) %>
                <div class="co-section-label">
                  Order summary
                  <span class="co-section-count">· {length(item_line_items)} {if length(item_line_items) == 1, do: "item", else: "items"}</span>
                </div>
                <%= for item <- item_line_items do %>
                  <% {iw, ic} = format_amount_parts(item["total_amount"] || item["unit_amount"]) %>
                  <div class="co-item-card">
                    <div class="co-item-thumb">
                      <%= if item["image_url"] && item["image_url"] != "" do %>
                        <img src={item["image_url"]} alt={item["description"]} class="co-item-thumb-img" />
                      <% else %>
                        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" style="color:var(--subtle-text)"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="12" cy="12" r="4"/></svg>
                      <% end %>
                    </div>
                    <div class="co-item-body">
                      <div class="co-item-name">{item["description"]}</div>
                      <div class="co-item-bottom">
                        <span class="co-item-qty">Qty {item["quantity"] || 1}</span>
                        <span class="co-item-price">{currency_symbol(@currency)}{iw}.{ic}</span>
                      </div>
                    </div>
                  </div>
                <% end %>
                <div class="co-totals-block">
                  <% {sub_w, sub_c} = format_amount_parts(@subtotal_amount) %>
                  <div class="co-total-row"><span>Subtotal</span><span>{currency_symbol(@currency)}{sub_w}.{sub_c}</span></div>
                  <%= if @shipping_amount > 0 do %>
                    <% {sh_w, sh_c} = format_amount_parts(@shipping_amount) %>
                    <div class="co-total-row"><span>Delivery</span><span>{currency_symbol(@currency)}{sh_w}.{sh_c}</span></div>
                  <% end %>
                  <%= if @tax_amount > 0 do %>
                    <% {tx_w, tx_c} = format_amount_parts(@tax_amount) %>
                    <div class="co-total-row"><span>Tax (VAT)</span><span>{currency_symbol(@currency)}{tx_w}.{tx_c}</span></div>
                  <% end %>
                  <%= if @discount_amount > 0 do %>
                    <% {dc_w, dc_c} = format_amount_parts(@discount_amount) %>
                    <div class="co-total-row co-total-row--discount">
                      <span class="co-disc-label">
                        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color:var(--success)"><polyline points="20.59 13.41 13.42 20.58 6.37 13.53 13.53 6.37 20.59 13.41"/><line x1="6" y1="6" x2="6.01" y2="6"/></svg>
                        Discount
                        <%= if first_discount && first_discount["description"] do %>
                          <span class="co-disc-badge">{first_discount["description"] |> String.replace(~r/[Pp]romo\s+code:?\s*/i, "") |> String.upcase()}</span>
                        <% end %>
                      </span>
                      <span>−{currency_symbol(@currency)}{dc_w}.{dc_c}</span>
                    </div>
                  <% end %>
                  <div class="co-grand-row">
                    <span class="co-grand-label">Total due</span>
                    <span class="co-grand-val">{currency_symbol(@currency)}{hero_w}.{hero_c}</span>
                  </div>
                </div>
              <% end %>

            </div><%!-- /co-panel-left --%>

            <%!-- ══ RIGHT PANEL: Payment Form ══ --%>
            <div class="co-panel-right">
              <div class="co-form-inner">

                <form phx-submit="submit_checkout" class="co-options-form">

                  <%!-- ── Contact information ── --%>
                  <%= if @collect_name or @collect_email or @collect_phone do %>
                    <div class="co-form-section">Contact information</div>

                    <%= if @collect_name do %>
                      <div class="co-f-group">
                        <label class="co-field-label" for="customer_name">Full name</label>
                        <div class="co-f-icon-wrap">
                          <div class="co-f-icon-pre">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                          </div>
                          <input
                            id="customer_name" name="customer_name" type="text"
                            class="co-f-icon-field"
                            value={@customer_name} placeholder="Kofi Asante"
                            autocomplete="name"
                            phx-change="change_customer_name" phx-debounce="blur"
                          />
                        </div>
                        <%= if @collection_errors["name"] do %>
                          <span class="co-error-text">{@collection_errors["name"]}</span>
                        <% end %>
                      </div>
                    <% end %>

                    <%= if @collect_email do %>
                      <div class="co-f-group">
                        <label class="co-field-label" for="customer_email">Email address</label>
                        <div class="co-f-icon-wrap">
                          <div class="co-f-icon-pre">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/></svg>
                          </div>
                          <input
                            id="customer_email" name="customer_email" type="email"
                            class="co-f-icon-field"
                            value={@customer_email} placeholder="kofi@example.com"
                            autocomplete="email" inputmode="email"
                            phx-change="change_customer_email" phx-debounce="blur"
                          />
                        </div>
                        <%= if @collection_errors["email"] do %>
                          <span class="co-error-text">{@collection_errors["email"]}</span>
                        <% end %>
                      </div>
                    <% end %>

                    <%= if @collect_phone do %>
                      <div class="co-f-group">
                        <label class="co-field-label" for="customer_phone">Phone number</label>
                        <div class="co-f-icon-wrap">
                          <div class="co-f-icon-pre">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 12 19.79 19.79 0 0 1 1.61 3.42C1.6 2.3 2.46 1.4 3.58 1.4h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L7.91 9.14a16 16 0 0 0 6 6l1-1.52a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
                          </div>
                          <input
                            id="customer_phone" name="customer_phone" type="tel"
                            class="co-f-icon-field"
                            value={@customer_phone} placeholder="+233 24 000 0000"
                            autocomplete="tel" inputmode="tel"
                            phx-change="change_customer_phone" phx-debounce="blur"
                          />
                        </div>
                        <%= if @collection_errors["phone"] do %>
                          <span class="co-error-text">{@collection_errors["phone"]}</span>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>

                  <%!-- ── Payment method ── --%>
                  <div class="co-form-section">Payment method</div>

                    <%= if @error do %>
                      <div class="co-alert co-alert--error">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
                        <span>{@error}</span>
                      </div>
                    <% end %>

                    <div class="co-method-list">

                      <%!-- Mobile Money radio item --%>
                      <%= if method_enabled?(@methods, "mobile_money") do %>
                        <div class={"co-method-item#{if @selected_method == "mobile_money", do: " co-method-item--on"}"}
                             phx-click="select_method" phx-value-method="mobile_money">
                          <div class="co-method-item-hd">
                            <div class="co-radio-dot"><div class="co-radio-inner"></div></div>
                            <span class="co-method-item-icon">
                              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg>
                            </span>
                            <span class="co-method-item-name">Mobile Money</span>
                            <span class="co-method-item-logos">
                              <img src="/images/momo.png" width="20" height="20" style="border-radius:4px;object-fit:cover;display:block;" alt="MTN">
                              <img src="/images/telecel.png" width="20" height="20" style="border-radius:4px;object-fit:cover;display:block;" alt="Telecel">
                              <img src="/images/at.png" width="20" height="20" style="border-radius:4px;object-fit:cover;display:block;" alt="AT">
                            </span>
                          </div>
                          <%= if @selected_method == "mobile_money" do %>
                            <div class="co-method-item-body">
                              <div class="co-f-group">
                                <label class="co-field-label">Network</label>
                                <div class="co-net-tabs">
                                  <%= for net <- @networks do %>
                                    <button type="button"
                                      class={"co-net-tab co-net-tab--#{net.css}#{if @selected_network == net.id, do: " co-net-tab--active"}"}
                                      phx-click="select_network" phx-value-network={net.id}>
                                      <span class="co-net-tab-logo">{raw(network_svg(net.id))}</span>
                                      <span class="co-net-tab-label">{net.label}</span>
                                    </button>
                                  <% end %>
                                </div>
                              </div>
                              <%= if @selected_network do %>
                                <div class="co-f-group" style="margin-bottom:0;">
                                  <label class="co-field-label" for="phone">Mobile Money number</label>
                                  <div class={"co-phone-box#{if @phone_error, do: " co-phone-box--error"}"}>
                                    <span class="co-flag-pill">
                                      <span class="co-flag">🇬🇭</span>
                                      <span class="co-calling-code">+233</span>
                                    </span>
                                    <input id="phone" name="phone" type="tel"
                                      class="co-input co-phone-input"
                                      value={@phone} placeholder="024 000 0000"
                                      autocomplete="tel-national" inputmode="numeric" maxlength="10"
                                      phx-change="change_phone" />
                                    <%= if @detected_network do %>
                                      <img
                                        src={network_logo(@detected_network)}
                                        width="20" height="20"
                                        style="border-radius:4px;object-fit:cover;display:block;margin-right:8px;flex-shrink:0;"
                                        alt={@detected_network}
                                      />
                                    <% end %>
                                  </div>
                                  <%= if @phone_error do %>
                                    <span class="co-error-text">{@phone_error}</span>
                                  <% end %>
                                </div>
                              <% else %>
                                <p class="co-net-prompt">Select your network above to continue</p>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>

                      <%!-- Card radio item --%>
                      <%= if method_enabled?(@methods, "card") do %>
                        <div class={"co-method-item#{if @selected_method == "card", do: " co-method-item--on"}"}
                             phx-click="select_method" phx-value-method="card">
                          <div class="co-method-item-hd">
                            <div class="co-radio-dot"><div class="co-radio-inner"></div></div>
                            <span class="co-method-item-icon">
                              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="4" width="22" height="16" rx="2" ry="2"/><line x1="1" y1="10" x2="23" y2="10"/></svg>
                            </span>
                            <span class="co-method-item-name">Card</span>
                            <span class="co-method-item-logos">
                              {raw(card_brand_svg("visa"))}
                              {raw(card_brand_svg("mastercard"))}
                              {raw(card_brand_svg("verve"))}
                            </span>
                          </div>
                          <%= if @selected_method == "card" do %>
                            <div class="co-method-item-body">
                              <%= if @simulation_mode do %>
                              <div class="co-sandbox-notice">
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;margin-top:2px"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
                                <div>
                                  <p class="co-sandbox-title">Simulation mode — use test cards</p>
                                  <div class="co-sandbox-cards">
                                    <div><code>4242 4242 4242 4242</code> — Authorised</div>
                                    <div><code>4000 0000 0000 0002</code> — Declined</div>
                                    <div><code>4000 0000 0000 9995</code> — Insufficient funds</div>
                                  </div>
                                  <p style="margin-top:4px;font-size:0.7rem;opacity:0.75">Expiry: <code>12/28</code> · CVV: <code>123</code> · any name.</p>
                                </div>
                              </div>
                              <% end %>

                              <%= if @card_psp == "stripe" do %>
                                <%!-- Stripe Elements — card entry is handled by Stripe.js --%>
                                <div id="stripe-card-form"
                                     phx-hook="StripeCard"
                                     phx-update="ignore"
                                     data-stripe-pk={@stripe_pk}>
                                  <div id="stripe-card-element" style="padding:10px 12px;border:1.5px solid #e5e7eb;border-radius:8px;background:#fff;min-height:40px;"></div>
                                </div>
                                <%= if @stripe_card_error do %>
                                  <span class="co-error-text" style="margin-top:4px;">{@stripe_card_error}</span>
                                <% end %>
                                <%= if not @simulation_mode and @checkout_mode == "sandbox" do %>
                                  <div class="co-sandbox-notice" style="margin-top:8px;">
                                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;margin-top:2px"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
                                    <div>
                                      <p class="co-sandbox-title">Stripe sandbox — use Stripe test cards</p>
                                      <div class="co-sandbox-cards">
                                        <div><code>4242 4242 4242 4242</code> — Visa success</div>
                                        <div><code>4000 0000 0000 0002</code> — Declined</div>
                                        <div><code>4000 0000 0000 9995</code> — Insufficient funds</div>
                                      </div>
                                      <p style="margin-top:4px;font-size:0.7rem;opacity:0.75">Expiry: <code>12/28</code> · CVV: <code>123</code> · any name.</p>
                                    </div>
                                  </div>
                                <% end %>
                              <% else %>
                                <%!-- Native card form — for future GhIPSS integration --%>
                                <div class="co-field">
                                  <label class="co-field-label" for="card_number">Card number</label>
                                  <div class={"co-card-number-box#{if @card_errors["number"], do: " co-card-box--error"}"}>
                                    <input id="card_number" name="card_number" type="text" inputmode="numeric"
                                      value={@card_number} placeholder="0000 0000 0000 0000"
                                      maxlength="19" autocomplete="cc-number" class="co-card-number-input"
                                      phx-change="change_card_number" />
                                    <%= if @card_brand do %>
                                      <span class="co-card-brand-badge">{raw(card_brand_svg(@card_brand))}</span>
                                    <% end %>
                                  </div>
                                  <%= if @card_errors["number"] do %>
                                    <span class="co-error-text">{@card_errors["number"]}</span>
                                  <% end %>
                                </div>
                                <div class="co-card-row">
                                  <div class="co-field">
                                    <label class="co-field-label" for="card_expiry">Expiry</label>
                                    <input id="card_expiry" name="card_expiry" type="text" inputmode="numeric"
                                      value={@card_expiry} placeholder="MM/YY" maxlength="5" autocomplete="cc-exp"
                                      class={"co-input#{if @card_errors["expiry"], do: " co-input--error"}"}
                                      phx-change="change_card_expiry" />
                                    <%= if @card_errors["expiry"] do %>
                                      <span class="co-error-text">{@card_errors["expiry"]}</span>
                                    <% end %>
                                  </div>
                                  <div class="co-field">
                                    <label class="co-field-label" for="card_cvv">CVV</label>
                                    <input id="card_cvv" name="card_cvv" type="text" inputmode="numeric"
                                      value={@card_cvv} placeholder="•••" maxlength="4" autocomplete="cc-csc"
                                      class={"co-input#{if @card_errors["cvv"], do: " co-input--error"}"}
                                      phx-change="change_card_cvv" />
                                    <%= if @card_errors["cvv"] do %>
                                      <span class="co-error-text">{@card_errors["cvv"]}</span>
                                    <% end %>
                                  </div>
                                </div>
                                <div class="co-field">
                                  <label class="co-field-label" for="card_name">Name on card</label>
                                  <input id="card_name" name="card_name" type="text"
                                    value={@card_name} placeholder="JOHN DOE"
                                    autocomplete="cc-name" style="text-transform:uppercase"
                                    class={"co-input#{if @card_errors["name"], do: " co-input--error"}"}
                                    phx-change="change_card_name" />
                                  <%= if @card_errors["name"] do %>
                                    <span class="co-error-text">{@card_errors["name"]}</span>
                                  <% end %>
                                </div>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>

                      <%!-- Bank Transfer radio item --%>
                      <%= if method_enabled?(@methods, "bank_transfer") do %>
                        <div class={"co-method-item#{if @selected_method == "bank_transfer", do: " co-method-item--on"}"}
                             phx-click="select_method" phx-value-method="bank_transfer">
                          <div class="co-method-item-hd">
                            <div class="co-radio-dot"><div class="co-radio-inner"></div></div>
                            <span class="co-method-item-icon">
                              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="22" x2="21" y2="22"/><line x1="6" y1="18" x2="6" y2="11"/><line x1="10" y1="18" x2="10" y2="11"/><line x1="14" y1="18" x2="14" y2="11"/><line x1="18" y1="18" x2="18" y2="11"/><polygon points="12 2 20 7 4 7"/></svg>
                            </span>
                            <span class="co-method-item-name">Bank Transfer</span>
                            <span style="font-size:10.5px;color:var(--muted-text);font-weight:500;">{if @bank_transfer_psp == "paystack", do: "Paystack", else: "GhIPSS"}</span>
                          </div>
                          <%= if @selected_method == "bank_transfer" do %>
                            <div class="co-method-item-body">
                              <div class="co-bank-info-notice">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;margin-top:2px"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
                                <div>
                                  <p class="co-bank-notice-title">Unique account generated per payment</p>
                                  <p class="co-bank-notice-desc">
                                    Click Pay to generate a dedicated bank account for this transaction.
                                    Transfer the exact amount via <strong>{if @bank_transfer_psp == "paystack", do: "Paystack bank transfer", else: "GhIPSS Instant Pay"}</strong> —
                                    your payment is confirmed automatically in seconds.
                                  </p>
                                </div>
                              </div>
                            </div>
                          <% end %>
                        </div>
                      <% end %>

                    </div><%!-- /co-method-list --%>

                  <%!-- ── T&Cs ── --%>
                  <%= if @terms_enabled do %>
                    <div class="co-terms-row">
                      <input
                        type="checkbox" id="co-terms-check" class="co-terms-checkbox"
                        checked={@terms_accepted} phx-click="toggle_terms"
                      />
                      <label for="co-terms-check" class="co-terms-label">
                        <%= if @terms_url && @terms_url != "" do %>
                          I agree to the
                          <a href={@terms_url} target="_blank" rel="noopener noreferrer" class="co-terms-link">
                            {String.replace(@terms_label, "I agree to the ", "")}
                          </a>
                        <% else %>
                          {@terms_label}
                        <% end %>
                      </label>
                    </div>
                    <%= if @terms_error do %>
                      <span class="co-error-text">{@terms_error}</span>
                    <% end %>
                  <% end %>

                  <%!-- ── Pay summary ── --%>
                  <% {whole, cents} = format_amount_parts(@total_amount) %>
                  <% pay_label = cond do
                    @cta_text && @cta_text != "" -> @cta_text
                    @selected_method == "bank_transfer" -> "Generate Transfer Account"
                    true -> "Pay #{currency_symbol(@currency)}#{whole}.#{cents}"
                  end %>

                  <div class="co-pay-sum" id="pay-sum">
                    <%= if @line_items != [] do %>
                      <% {sub_w, sub_c} = format_amount_parts(@subtotal_amount) %>
                      <div class="co-ps-row"><span>Subtotal</span><span>{currency_symbol(@currency)}{sub_w}.{sub_c}</span></div>
                      <%= if @shipping_amount > 0 do %>
                        <% {sh_w, sh_c} = format_amount_parts(@shipping_amount) %>
                        <div class="co-ps-row"><span>Delivery</span><span>{currency_symbol(@currency)}{sh_w}.{sh_c}</span></div>
                      <% end %>
                      <%= if @tax_amount > 0 do %>
                        <% {tx_w, tx_c} = format_amount_parts(@tax_amount) %>
                        <div class="co-ps-row"><span>Tax (VAT)</span><span>{currency_symbol(@currency)}{tx_w}.{tx_c}</span></div>
                      <% end %>
                    <% end %>
                    <%= if @discount_amount > 0 do %>
                      <% {dc_w, dc_c} = format_amount_parts(@discount_amount) %>
                      <div class="co-ps-row co-ps-row--discount"><span>Discount</span><span>−{currency_symbol(@currency)}{dc_w}.{dc_c}</span></div>
                    <% end %>
                    <div class="co-ps-total"><span>Total due</span><span>{currency_symbol(@currency)}{whole}.{cents}</span></div>
                  </div>

                  <button type="submit" class="co-btn-pay" phx-disable-with="Processing…">
                    <span>{pay_label}</span>
                    <svg class="co-btn-pay-lock" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                      <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                    </svg>
                  </button>

                  <div class="co-trust-footer">
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="color:var(--success);flex-shrink:0;">
                      <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                    </svg>
                    Secure &amp; encrypted payment
                    <span style="color:var(--faint-text);">·</span>
                    <a href="#">Learn more</a>
                  </div>

                  <div class="co-right-footer">
                    Powered by Yagye
                    <span class="co-rf-sep">•</span>
                    <a href="#">Terms</a>
                    <span class="co-rf-sep">•</span>
                    <a href="#">Privacy</a>
                  </div>

                  <%= if @cancel_url && external_url?(@cancel_url) do %>
                    <div class="co-cancel-wrap">
                      <a href={@cancel_url} class="co-cancel-link">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                          <line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/>
                        </svg>
                        Cancel and return
                      </a>
                    </div>
                  <% end %>

                </form>
              </div><%!-- /co-form-inner --%>
            </div><%!-- /co-panel-right --%>
          </div>

      <% end %>

      <footer class="co-page-footer">
        Powered by <strong>Yagye</strong>
      </footer>
    </div>

    <%= if @brand_color || @font_family do %>
      {raw(build_dynamic_style(@brand_color, @font_family))}
    <% end %>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp init_from_session(socket, session) do
    now_unix = System.os_time(:second)
    expires = parse_expires(session["expires_at"])
    page_state = resolve_state(session["state"], expires, now_unix)
    methods = parse_methods(session["checkout_layout"], session["allowed_methods"])
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
      logo_url: (session["checkout_layout"] || %{})["logo_url"],
      simulation_mode: session["mode"] == "simulation",
      checkout_mode: session["mode"] || "live"
    )
    |> then(fn sock ->
      layout = session["checkout_layout"] || %{}
      terms  = layout["terms"] || %{}
      trust  = layout["trust_badges"] || %{}
      assign(sock,
        brand_color:            sanitize_hex_color(layout["brand_color"]),
        font_family:            layout["font_family"],
        checkout_headline:      layout["headline"],
        cta_text:               layout["cta_text"],
        checkout_business_name: layout["business_name"],
        terms_enabled:          terms["enabled"] == true,
        terms_label:            terms["label"] || "I agree to the Terms & Conditions",
        terms_url:              terms["url"] || "",
        terms_accepted:         false,
        terms_error:            nil,
        trust_ssl:              Map.get(trust, "ssl", true) != false,
        trust_instant:          Map.get(trust, "instant", true) != false,
        trust_bog:              trust["bog"] == true
      )
    end)
    |> assign_psp_context(session["psp_context"])
    |> maybe_start_poll(page_state)
  end

  defp assign_psp_context(socket, nil), do: socket

  defp assign_psp_context(socket, psp_context) when is_map(psp_context) do
    card_entry       = psp_context["card"] || %{}
    bt_entry         = psp_context["bank_transfer"] || %{}
    momo_entry       = psp_context["mobile_money"] || %{}

    assign(socket,
      card_psp:          card_entry["code"],
      stripe_pk:         card_entry["public_key"],
      bank_transfer_psp: bt_entry["code"],
      momo_psp:          momo_entry["code"]
    )
  end

  # `allowed_methods` from the session is authoritative for which methods appear.
  # `checkout_layout.methods` carries visual config (tile_style, rails) only.
  defp parse_methods(layout, allowed) do
    allowed_ids = if is_list(allowed) and allowed != [], do: allowed, else: ~w[mobile_money card bank_transfer]
    layout_methods = (layout || %{})["methods"] || []

    base = [
      %{"id" => "mobile_money",  "label" => "Mobile Money"},
      %{"id" => "card",          "label" => "Credit / Debit Card"},
      %{"id" => "bank_transfer", "label" => "Bank Transfer"}
    ]

    base
    |> Enum.filter(& &1["id"] in allowed_ids)
    |> Enum.map(fn m ->
      saved = Enum.find(layout_methods, & &1["id"] == m["id"]) || %{}
      Map.merge(m, Map.take(saved, ["tile_style", "rails"]))
    end)
    |> then(fn ms -> if ms == [], do: default_methods(), else: ms end)
  end

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
      logo_url: nil,
      card_number: "",
      card_expiry: "",
      card_cvv: "",
      card_name: "",
      card_errors: %{},
      card_brand: nil,
      processing_method: "mobile_money",
      virtual_account: nil,
      va_expires_unix: nil,
      now_unix: System.os_time(:second),
      simulation_mode: false,
      checkout_mode: "live",
      brand_color: nil,
      font_family: nil,
      checkout_headline: nil,
      cta_text: nil,
      terms_enabled: false,
      terms_label: "I agree to the Terms & Conditions",
      terms_url: "",
      terms_accepted: false,
      terms_error: nil,
      trust_ssl: true,
      trust_instant: true,
      trust_bog: false,
      checkout_business_name: nil,
      submitting: false,
      submission_token: nil,
      user_agent_hash: nil,
      escrow_hold: nil,
      escrow_confirm_modal: false,
      escrow_confirming: false,
      escrow_disputing: false,
      dispute_note: "",
      card_psp: nil,
      stripe_pk: nil,
      bank_transfer_psp: nil,
      momo_psp: nil,
      stripe_card_error: nil
    )
  end

  defp capture_ua_hash(socket) do
    case get_connect_info(socket, :x_headers) do
      headers when is_list(headers) ->
        case List.keyfind(headers, "user-agent", 0) do
          {_, ua} -> Base.encode16(:crypto.hash(:sha256, ua), case: :lower)
          nil -> nil
        end
      _ ->
        nil
    end
  end

  defp resolve_state("completed", _e, _n), do: :done
  defp resolve_state("cancelled", _e, _n), do: :cancelled
  defp resolve_state("expired",   _e, _n), do: :expired
  defp resolve_state(_s, expires, now) when is_integer(expires) and expires < now, do: :expired
  defp resolve_state("processing", _e, _n), do: :processing
  defp resolve_state("escrow_held",     _e, _n), do: :escrow_held
  defp resolve_state("escrow_disputed", _e, _n), do: :escrow_disputed
  defp resolve_state(_s, _e, _n), do: :form

  defp maybe_start_poll(socket, state) when state in [:processing, :awaiting_transfer] do
    if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)
    socket
  end

  defp maybe_start_poll(socket, _), do: socket

  defp submit_mobile_money(socket, phone) do
    %{assigns: %{session_public_id: sid, selected_network: sel_net,
                  customer_email: email, customer_phone: cph, customer_name: name,
                  submission_token: token, user_agent_hash: ua_hash}} = socket
    network = sel_net || detect_network(phone)

    attrs =
      %{method: "mobile_money", msisdn: phone, network: network, submission_token: token}
      |> maybe_put(:customer_email, email)
      |> maybe_put(:customer_phone, cph)
      |> maybe_put(:customer_name, name)
      |> maybe_put(:user_agent_hash, ua_hash)

    case CoreClient.pay_session(sid, attrs) do
      {:ok, %{"payment_public_id" => pay_id}} ->
        if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)
        {:noreply, assign(socket, submitting: false, page_state: :processing, payment_public_id: pay_id, poll_count: 0, error: nil, phone_error: nil, processing_method: "mobile_money", phone: phone)}

      {:error, _} ->
        {:noreply, assign(socket, submitting: false, error: "We couldn't process your payment. Please verify your mobile number and balance.")}
    end
  end

  defp submit_card(socket) do
    %{assigns: %{session_public_id: sid, card_number: cn,
                  customer_email: email, customer_phone: cph, customer_name: name,
                  submission_token: token, user_agent_hash: ua_hash}} = socket
    digits = String.replace(cn, " ", "")

    attrs =
      %{method: "card", card_number: digits, submission_token: token}
      |> maybe_put(:customer_email, email)
      |> maybe_put(:customer_phone, cph)
      |> maybe_put(:customer_name, name)
      |> maybe_put(:user_agent_hash, ua_hash)

    case CoreClient.pay_session(sid, attrs) do
      {:ok, %{"payment_public_id" => pay_id}} ->
        if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)
        {:noreply, assign(socket, submitting: false, page_state: :processing, payment_public_id: pay_id, poll_count: 0, error: nil, card_errors: %{}, processing_method: "card")}

      {:error, _} ->
        {:noreply, assign(socket, submitting: false, error: "Card payment failed. Please check your details and try again.")}
    end
  end

  defp submit_card_stripe(socket, payment_method_id) do
    %{assigns: %{session_public_id: sid,
                  customer_email: email, customer_phone: cph, customer_name: name,
                  submission_token: token, user_agent_hash: ua_hash}} = socket

    attrs =
      %{method: "card", payment_method_id: payment_method_id, submission_token: token}
      |> maybe_put(:customer_email, email)
      |> maybe_put(:customer_phone, cph)
      |> maybe_put(:customer_name, name)
      |> maybe_put(:user_agent_hash, ua_hash)

    case CoreClient.pay_session(sid, attrs) do
      {:ok, %{"payment_public_id" => pay_id}} ->
        if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)
        {:noreply, assign(socket, submitting: false, page_state: :processing, payment_public_id: pay_id, poll_count: 0, error: nil, stripe_card_error: nil, processing_method: "card")}

      {:error, _} ->
        {:noreply, assign(socket, submitting: false, error: "Card payment failed. Please check your details and try again.")}
    end
  end

  defp submit_bank_transfer(socket) do
    %{assigns: %{session_public_id: sid,
                  customer_email: email, customer_phone: cph, customer_name: name,
                  submission_token: token, user_agent_hash: ua_hash}} = socket

    attrs =
      %{method: "bank_transfer", submission_token: token}
      |> maybe_put(:customer_email, email)
      |> maybe_put(:customer_phone, cph)
      |> maybe_put(:customer_name, name)
      |> maybe_put(:user_agent_hash, ua_hash)

    case CoreClient.pay_session(sid, attrs) do
      {:ok, %{"payment_public_id" => pay_id}} ->
        if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)

        {:noreply,
         assign(socket,
           submitting: false,
           page_state: :awaiting_transfer,
           payment_public_id: pay_id,
           poll_count: 0,
           error: nil,
           processing_method: "bank_transfer",
           virtual_account: nil,
           va_expires_unix: nil
         )}

      {:error, _} ->
        {:noreply, assign(socket, submitting: false, error: "We couldn't generate a transfer account. Please try again.")}
    end
  end

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp finalize(socket, session_id, pay_id) do
    socket = push_event(socket, "confetti", %{})

    case CoreClient.complete_session(session_id, pay_id) do
      {:ok, %{"success_url" => url}} when is_binary(url) and url != "" ->
        sid = socket.assigns.session_public_id
        final_url = String.replace(url, "{CHECKOUT_SESSION_ID}", sid || "")
        if connected?(socket) and external_url?(final_url) do
          Process.send_after(self(), {:auto_redirect, final_url}, 3_500)
        end
        {:noreply, assign(socket, page_state: :done, success_url: final_url)}

      _ ->
        {:noreply, assign(socket, page_state: :done)}
    end
  end

  defp finalize_escrow(socket, pay_id) do
    case CoreClient.get_escrow_hold(pay_id) do
      {:ok, hold} ->
        {:noreply, assign(socket, page_state: :escrow_held, escrow_hold: hold)}

      _ ->
        {:noreply, assign(socket, page_state: :escrow_held, escrow_hold: %{})}
    end
  end

  @doc false
  def external_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        host not in ["localhost", "pay.yagye.com"]

      _ ->
        false
    end
  end

  def external_url?(_), do: false

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



  defp method_label("mobile_money"),  do: "Mobile Money"
  defp method_label("card"),          do: "Credit / Debit Card"
  defp method_label("bank_transfer"), do: "Bank Transfer"
  defp method_label(m),               do: m

  defp merchant_brand_name(%{"merchant_name" => name})
       when is_binary(name) and name != "",
       do: name

  defp merchant_brand_name(%{"metadata" => %{"merchant_name" => name}})
       when is_binary(name) and name != "",
       do: name

  defp merchant_brand_name(_), do: "Yagye"

  defp network_svg("MTN"),        do: ~s(<img src="/images/momo.png"    width="32" height="32" style="border-radius:7px;object-fit:cover;display:block;" alt="MTN MoMo">)
  defp network_svg("Telecel"),    do: ~s(<img src="/images/telecel.png" width="32" height="32" style="border-radius:7px;object-fit:cover;display:block;" alt="Telecel Cash">)
  defp network_svg("AirtelTigo"), do: ~s(<img src="/images/at.png"      width="32" height="32" style="border-radius:7px;object-fit:cover;display:block;" alt="AirtelTigo">)
  defp network_svg(_),            do: ~s(<span style="width:32px;height:32px;border-radius:7px;background:#E5E7EB;display:block;"></span>)

  defp network_logo("MTN"),        do: "/images/momo.png"
  defp network_logo("Telecel"),    do: "/images/telecel.png"
  defp network_logo("AirtelTigo"), do: "/images/at.png"
  defp network_logo(_),            do: "/images/momo.png"

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

  defp detect_card_brand(digits) when byte_size(digits) >= 1 do
    cond do
      String.starts_with?(digits, "4") -> "visa"
      String.starts_with?(digits, ["51", "52", "53", "54", "55"]) -> "mastercard"
      Regex.match?(~r/^2[2-7]/, digits) -> "mastercard"
      String.starts_with?(digits, ["5061", "6500", "6501"]) -> "verve"
      true -> nil
    end
  end

  defp detect_card_brand(_), do: nil

  defp validate_card(card_number, card_expiry, card_cvv, card_name) do
    digits = String.replace(card_number, " ", "")
    %{}
    |> then(fn e -> if String.length(digits) < 13, do: Map.put(e, "number", "Enter a valid card number"), else: e end)
    |> then(fn e -> if not valid_expiry?(card_expiry), do: Map.put(e, "expiry", "Enter a valid expiry (MM/YY)"), else: e end)
    |> then(fn e -> if String.length(card_cvv) < 3, do: Map.put(e, "cvv", "Enter your CVV"), else: e end)
    |> then(fn e -> if String.trim(card_name) == "", do: Map.put(e, "name", "Enter the name on your card"), else: e end)
  end

  defp valid_expiry?(expiry) do
    case String.split(expiry, "/") do
      [mm, yy] ->
        with {month, ""} <- Integer.parse(String.trim(mm)),
             {year, ""} <- Integer.parse(String.trim(yy)),
             true <- month in 1..12 do
          now = Date.utc_today()
          full_year = 2000 + year
          full_year > now.year or (full_year == now.year and month >= now.month)
        else
          _ -> false
        end
      _ -> false
    end
  end

  defp parse_va_expires(nil), do: nil

  defp parse_va_expires(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> nil
    end
  end

  defp format_countdown(nil, _now), do: "--:--"

  defp format_countdown(expires, now) when is_integer(expires) and is_integer(now) do
    remaining = max(expires - now, 0)
    mm = div(remaining, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    ss = rem(remaining, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{mm}:#{ss}"
  end

  defp format_countdown(_, _), do: "--:--"

  defp countdown_urgent?(nil, _now), do: false

  defp countdown_urgent?(expires, now) when is_integer(expires) and is_integer(now) do
    expires - now < 120
  end

  defp countdown_urgent?(_, _), do: false

  defp format_account_number(nil), do: "—"

  defp format_account_number(number) when is_binary(number) do
    number
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  @hex_color_regex ~r/^#[0-9A-Fa-f]{6}$/

  @doc false
  def sanitize_hex_color(color) when is_binary(color) do
    trimmed = String.trim(color)
    if Regex.match?(@hex_color_regex, trimmed), do: trimmed, else: nil
  end

  def sanitize_hex_color(_), do: nil

  @doc false
  def build_dynamic_style(nil, nil), do: ""

  def build_dynamic_style(brand_color, font_family) do
    safe_color = sanitize_hex_color(brand_color)

    if is_nil(safe_color) and is_nil(font_family) do
      ""
    else
      root_parts =
        [
          if safe_color do
            hover = darken_color(safe_color)
            rgb   = hex_to_rgb(safe_color)
            """
            --brand: #{safe_color};
            --brand-hover: #{hover};
            --brand-subtle: rgba(#{rgb}, 0.08);
            --brand-glow: rgba(#{rgb}, 0.15);
            """
          end,
          (if font_family, do: "--co-font: #{font_stack(font_family)};", else: nil)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      font_body =
        if font_family,
          do: "body, .co-checkout-container { font-family: var(--co-font); }",
          else: ""

      "<style>:root { #{root_parts} } #{font_body}</style>"
    end
  end

  defp darken_color(nil), do: "#323BD8"

  defp darken_color(hex) do
    hex = String.trim_leading(hex, "#")
    case Integer.parse(hex, 16) do
      {n, ""} ->
        r = max(div(n, 0x10000) - 25, 0)
        g = max(rem(div(n, 0x100), 0x100) - 25, 0)
        b = max(rem(n, 0x100) - 25, 0)
        "#" <>
          String.pad_leading(Integer.to_string(r, 16), 2, "0") <>
          String.pad_leading(Integer.to_string(g, 16), 2, "0") <>
          String.pad_leading(Integer.to_string(b, 16), 2, "0")
      _ -> "#323BD8"
    end
  end

  defp hex_to_rgb(nil), do: "61, 71, 245"

  defp hex_to_rgb(hex) do
    hex = String.trim_leading(hex, "#")
    case Integer.parse(hex, 16) do
      {n, ""} ->
        r = div(n, 0x10000)
        g = rem(div(n, 0x100), 0x100)
        b = rem(n, 0x100)
        "#{r}, #{g}, #{b}"
      _ -> "61, 71, 245"
    end
  end

  defp font_stack("inter"),       do: "'Inter', system-ui, sans-serif"
  defp font_stack("nunito"),      do: "'Nunito', system-ui, sans-serif"
  defp font_stack("playfair"),    do: "'Playfair Display', Georgia, serif"
  defp font_stack("roboto-slab"), do: "'Roboto Slab', Georgia, serif"
  defp font_stack(_),             do: "'Plus Jakarta Sans', system-ui, sans-serif"

end
