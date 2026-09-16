defmodule Simulator.Web.Live.SimulationLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Charges
  alias Simulator.Repo

  @wallet_presets [
    %{label: "MTN Approved", msisdn: "0241000001", network: "MTN", badge: "authorised"},
    %{label: "MTN Insufficient", msisdn: "0241000002", network: "MTN", badge: "declined"},
    %{label: "MTN Expired Prompt", msisdn: "0241000003", network: "MTN", badge: "pending"},
    %{label: "MTN Not Registered", msisdn: "0241000004", network: "MTN", badge: "declined"},
    %{label: "MTN No Webhook", msisdn: "0241000005", network: "MTN", badge: "pending"},
    %{label: "TELECEL Approved", msisdn: "0501000001", network: "TELECEL", badge: "authorised"},
    %{label: "TELECEL Insufficient", msisdn: "0501000002", network: "TELECEL", badge: "declined"},
    %{
      label: "AirtelTigo Approved",
      msisdn: "0571000001",
      network: "AIRTELTIGO",
      badge: "authorised"
    },
    %{
      label: "AirtelTigo Insufficient",
      msisdn: "0571000002",
      network: "AIRTELTIGO",
      badge: "declined"
    }
  ]

  @card_presets [
    %{label: "Visa Approved", card: "4242 4242 4242 4242", badge: "authorised"},
    %{label: "Do Not Honour", card: "4000 0000 0000 0002", badge: "declined"},
    %{label: "Insufficient Funds", card: "4000 0000 0000 9995", badge: "declined"},
    %{label: "Expired Card", card: "4000 0000 0000 0069", badge: "declined"},
    %{label: "Timeout", card: "4000 0000 0000 0119", badge: "pending"},
    %{label: "Provider Error", card: "4000 0000 0000 0259", badge: "pending"}
  ]

  @networks ~w[MTN TELECEL AIRTELTIGO]
  @currencies ~w[GHS NGN KES USD]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       account: load_account(),
       instrument: "WALLET",
       msisdn: "0241000001",
       network: "MTN",
       card_number: "4242 4242 4242 4242",
       amount_str: "100.00",
       currency: "GHS",
       result: nil,
       history: [],
       wallet_presets: @wallet_presets,
       card_presets: @card_presets,
       networks: @networks,
       currencies: @currencies
     )}
  end

  @impl true
  def handle_event("set_instrument", %{"type" => type}, socket) do
    {:noreply, assign(socket, instrument: type, result: nil)}
  end

  @impl true
  def handle_event("preset_wallet", %{"msisdn" => msisdn, "network" => network}, socket) do
    {:noreply, assign(socket, msisdn: msisdn, network: network)}
  end

  @impl true
  def handle_event("preset_card", %{"card" => card}, socket) do
    {:noreply, assign(socket, card_number: card)}
  end

  @impl true
  def handle_event("update_form", params, socket) do
    socket =
      socket
      |> put_if_present(:msisdn, params["msisdn"])
      |> put_if_present(:network, params["network"])
      |> put_if_present(:card_number, params["card_number"])
      |> put_if_present(:amount_str, params["amount"])
      |> put_if_present(:currency, params["currency"])

    {:noreply, socket}
  end

  @impl true
  def handle_event("fire", _params, %{assigns: %{account: nil}} = socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "No simulator account found — provision a provider in Core first."
     )}
  end

  def handle_event("fire", _params, socket) do
    a = socket.assigns
    amount_minor = parse_amount(a.amount_str)

    attrs =
      %{instrument_type: a.instrument, amount_minor: amount_minor, currency: a.currency}
      |> put_wallet_fields(a)
      |> put_card_fields(a)

    case Charges.create_charge(a.account, attrs) do
      {:ok, charge} ->
        entry = build_history_entry(charge, a)
        history = [entry | Enum.take(a.history, 9)]
        {:noreply, assign(socket, result: entry, history: history)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Charge failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page">
      <header class="page-header">
        <h1>Live Simulation</h1>
        <p class="subtitle">
          Fire test payments directly — no checkout session or seeded payment needed.
          Results appear in the <a href="/admin/charges" style="color: #0ea5e9;">Charge Feed</a>.
        </p>
      </header>

      <%= if @account == nil do %>
        <div class="sim-no-account">
          No simulator account found. Start Core and provision a provider to create one.
        </div>
      <% else %>
        <%= for {kind, msg} <- @flash do %>
          <div class={"flash flash-#{kind}"}>{msg}</div>
        <% end %>

        <div class="sim-layout">
          <div class="sim-form-col">
            <.instrument_tabs instrument={@instrument} />

            <%= if @instrument == "WALLET" do %>
              <.wallet_presets presets={@wallet_presets} />
            <% end %>

            <%= if @instrument == "CARD" do %>
              <.card_presets presets={@card_presets} />
            <% end %>

            <form phx-change="update_form" phx-submit="fire" class="sim-form">
              <%= if @instrument == "WALLET" do %>
                <.wallet_fields msisdn={@msisdn} network={@network} networks={@networks} />
              <% end %>

              <%= if @instrument == "CARD" do %>
                <.card_fields card_number={@card_number} />
              <% end %>

              <%= if @instrument == "BANK" do %>
                <div class="sim-note">
                  Bank transfers use the active scenario's rate distribution. No fixed inputs.
                </div>
              <% end %>

              <div class="sim-amount-row">
                <div class="sim-field">
                  <label>Amount</label>
                  <input
                    type="text"
                    name="amount"
                    value={@amount_str}
                    class="sim-input sim-input-sm"
                    inputmode="decimal"
                    autocomplete="off"
                  />
                </div>
                <div class="sim-field">
                  <label>Currency</label>
                  <select name="currency" class="sim-select sim-input-sm">
                    <%= for c <- @currencies do %>
                      <option value={c} selected={c == @currency}>{c}</option>
                    <% end %>
                  </select>
                </div>
              </div>

              <button type="submit" class="sim-fire-btn">
                Fire Charge →
              </button>
            </form>
          </div>

          <div class="sim-results-col">
            <%= if @result do %>
              <.result_panel result={@result} />
            <% end %>

            <%= if @history != [] do %>
              <.history_panel history={@history} />
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Components ────────────────────────────────────────────────────────────────

  attr(:instrument, :string, required: true)

  defp instrument_tabs(assigns) do
    ~H"""
    <div class="sim-tabs">
      <%= for {type, label} <- [{"WALLET", "Wallet"}, {"CARD", "Card"}, {"BANK", "Bank Transfer"}] do %>
        <button
          phx-click="set_instrument"
          phx-value-type={type}
          class={"sim-tab#{if @instrument == type, do: " active", else: ""}"}
          type="button"
        >
          {label}
        </button>
      <% end %>
    </div>
    """
  end

  attr(:presets, :list, required: true)

  defp wallet_presets(assigns) do
    ~H"""
    <div class="sim-presets">
      <span class="sim-presets-label">Quick pick</span>
      <%= for p <- @presets do %>
        <button
          phx-click="preset_wallet"
          phx-value-msisdn={p.msisdn}
          phx-value-network={p.network}
          class={"sim-preset sim-preset-#{p.badge}"}
          type="button"
        >
          {p.label}
        </button>
      <% end %>
    </div>
    """
  end

  attr(:presets, :list, required: true)

  defp card_presets(assigns) do
    ~H"""
    <div class="sim-presets">
      <span class="sim-presets-label">Quick pick</span>
      <%= for p <- @presets do %>
        <button
          phx-click="preset_card"
          phx-value-card={p.card}
          class={"sim-preset sim-preset-#{p.badge}"}
          type="button"
        >
          {p.label}
        </button>
      <% end %>
    </div>
    """
  end

  attr(:msisdn, :string, required: true)
  attr(:network, :string, required: true)
  attr(:networks, :list, required: true)

  defp wallet_fields(assigns) do
    ~H"""
    <div class="sim-field-row">
      <div class="sim-field sim-field-grow">
        <label>MSISDN</label>
        <input
          type="tel"
          name="msisdn"
          value={@msisdn}
          class="sim-input"
          autocomplete="off"
          placeholder="0241000001"
        />
      </div>
      <div class="sim-field">
        <label>Network</label>
        <select name="network" class="sim-select">
          <%= for n <- @networks do %>
            <option value={n} selected={n == @network}>{n}</option>
          <% end %>
        </select>
      </div>
    </div>
    """
  end

  attr(:card_number, :string, required: true)

  defp card_fields(assigns) do
    ~H"""
    <div class="sim-field">
      <label>Card Number</label>
      <input
        type="text"
        name="card_number"
        value={@card_number}
        class="sim-input sim-input-mono"
        autocomplete="off"
        placeholder="4242 4242 4242 4242"
        maxlength="19"
      />
    </div>
    """
  end

  attr(:result, :map, required: true)

  defp result_panel(assigns) do
    ~H"""
    <div class="sim-result-card">
      <div class="sim-result-header">
        <span class="sim-result-label">Last Result</span>
        <span class={"badge badge-#{state_badge_slug(@result.state)}"}>{@result.state}</span>
      </div>
      <div class="sim-result-rows">
        <.kv label="Ref" value={@result.ref} mono={true} />
        <.kv label="Input" value={@result.label} mono={false} />
        <%= if @result.decline_code do %>
          <.kv label="Decline" value={@result.decline_code} mono={true} />
        <% end %>
        <%= if @result.state == "PENDING_AUTH" and @result.instrument == "WALLET" do %>
          <div class="sim-result-note">
            Webhook will be delivered to the account's webhook URL once the prompt resolves.
          </div>
        <% end %>
        <%= if @result.state == "PENDING_AUTH" and @result.instrument in ["CARD", "BANK"] do %>
          <div class="sim-result-note">
            Charge is stuck in PENDING_AUTH — timeout or provider error scenario.
            Use StuckPaymentScannerWorker to recover.
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:history, :list, required: true)

  defp history_panel(assigns) do
    ~H"""
    <div class="sim-history">
      <div class="sim-history-header">
        History <span class="sim-history-note">(this session)</span>
      </div>
      <table class="sim-history-table">
        <tbody>
          <%= for entry <- @history do %>
            <tr>
              <td class="mono" style="color: #475569; font-size: .75rem;">{entry.ref}</td>
              <td style="font-size: .8rem; color: #64748b;">{entry.label}</td>
              <td>
                <span class={"badge badge-#{state_badge_slug(entry.state)}"}>{entry.state}</span>
              </td>
              <td style="font-size: .75rem; color: #334155; text-align: right;">
                {time_ago(entry.fired_at)}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:mono, :boolean, default: false)

  defp kv(assigns) do
    ~H"""
    <div class="sim-kv">
      <span class="sim-kv-label">{@label}</span>
      <span class={"sim-kv-value#{if @mono, do: " mono", else: ""}"}>{@value}</span>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp load_account do
    Repo.all(Account) |> List.first() |> maybe_preload()
  end

  defp maybe_preload(nil), do: nil
  defp maybe_preload(account), do: Repo.preload(account, :default_scenario)

  defp put_if_present(socket, _key, nil), do: socket
  defp put_if_present(socket, _key, ""), do: socket
  defp put_if_present(socket, key, val), do: assign(socket, key, val)

  defp put_wallet_fields(attrs, %{instrument: "WALLET"} = a) do
    Map.merge(attrs, %{msisdn: a.msisdn, network: a.network})
  end

  defp put_wallet_fields(attrs, _), do: attrs

  defp put_card_fields(attrs, %{instrument: type} = a) when type in ["CARD", "BANK"] do
    Map.put(attrs, :card_number, a.card_number)
  end

  defp put_card_fields(attrs, _), do: attrs

  defp parse_amount(str) do
    case Float.parse(to_string(str)) do
      {f, _} -> round(f * 100)
      :error -> 10_000
    end
  end

  defp build_history_entry(charge, a) do
    %{
      ref: short_ref(charge.charge_ref),
      state: charge.state,
      decline_code: charge.decline_code,
      instrument: a.instrument,
      label: input_label(a),
      fired_at: DateTime.utc_now()
    }
  end

  defp input_label(%{instrument: "WALLET"} = a), do: "#{a.msisdn} (#{a.network})"
  defp input_label(%{instrument: "CARD"} = a), do: a.card_number
  defp input_label(%{instrument: "BANK"}), do: "Bank transfer"
  defp input_label(_), do: "—"

  defp short_ref(ref) when is_binary(ref) do
    "gw_···" <> String.slice(ref, -8, 8)
  end

  defp state_badge_slug(state) do
    state |> String.downcase() |> String.replace("_", "-")
  end

  defp time_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end
end
