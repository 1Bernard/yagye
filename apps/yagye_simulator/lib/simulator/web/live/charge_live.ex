defmodule Simulator.Web.Live.ChargeLive do
  use Phoenix.LiveView

  import Ecto.Query

  alias Simulator.Charges.Schemas.Charge
  alias Simulator.Charges.Schemas.WalletPrompt
  alias Simulator.Repo
  alias Simulator.Webhooks

  @refresh_ms 2_000
  @feed_limit 60

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)
    {:ok, assign(socket, charges: load_charges(), feed_limit: @feed_limit)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, charges: load_charges())}
  end

  @impl true
  def handle_event("resend_webhook", %{"charge-ref" => ref, "account-id" => account_id}, socket) do
    case Webhooks.enqueue_delivery(account_id, ref) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Webhook re-queued for #{short_ref(ref)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to re-queue: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page">
      <header class="page-header">
        <h1>
          Live Charge Feed
          <span class="live-dot" title="Refreshes every 2s"></span>
        </h1>
        <p class="subtitle">
          Last {@feed_limit} charges — newest first.
          Use <strong style="color: #94a3b8;">Resend</strong> to re-deliver a webhook Core may have missed.
        </p>
      </header>

      <%= for {kind, msg} <- @flash do %>
        <div class={"flash flash-#{kind}"}>{msg}</div>
      <% end %>

      <%= if @charges == [] do %>
        <div class="empty-state">No charges yet. Fire a payment through Core to see it here.</div>
      <% else %>
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Ref</th>
              <th>Instrument</th>
              <th>MSISDN / Network</th>
              <th style="text-align: right">Amount</th>
              <th>State</th>
              <th>Decline</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <%= for c <- @charges do %>
              <tr>
                <td class="time-cell">{time_ago(c.created_at)}</td>
                <td class="mono">{short_ref(c.charge_ref)}</td>
                <td><span class={instrument_chip(c.instrument_type)}>{c.instrument_type}</span></td>
                <td class="msisdn-cell">
                  <%= if c.msisdn do %>
                    {c.msisdn}<span class="network">{c.network}</span>
                  <% else %>
                    <span style="color: #334155">—</span>
                  <% end %>
                </td>
                <td class="amount-cell" style="text-align: right">{format_amount(c.amount_minor, c.currency)}</td>
                <td><span class={state_badge(c.state)}>{c.state}</span></td>
                <td>
                  <%= if c.decline_code do %>
                    <span class="decline-code">{c.decline_code}</span>
                  <% end %>
                </td>
                <td>
                  <%= if c.instrument_type == "WALLET" do %>
                    <button
                      class="btn-resend"
                      phx-click="resend_webhook"
                      phx-value-charge-ref={c.charge_ref}
                      phx-value-account-id={c.account_id}
                    >
                      Resend
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  # ── Data ─────────────────────────────────────────────────────────────────────

  defp load_charges do
    from(c in Charge,
      left_join: wp in WalletPrompt,
      on: wp.charge_id == c.id,
      select: %{
        id: c.id,
        account_id: c.account_id,
        charge_ref: c.charge_ref,
        instrument_type: c.instrument_type,
        amount_minor: c.amount_minor,
        currency: c.currency,
        state: c.state,
        decline_code: c.decline_code,
        created_at: c.created_at,
        msisdn: wp.msisdn,
        network: wp.network
      },
      order_by: [desc: c.created_at],
      limit: @feed_limit
    )
    |> Repo.all()
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp short_ref(ref) when is_binary(ref) do
    suffix = String.slice(ref, -8, 8)
    "gw_···#{suffix}"
  end

  defp time_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end

  defp format_amount(minor, currency) when is_integer(minor) do
    major = minor / 100
    formatted = :erlang.float_to_binary(major, decimals: 2)
    "#{currency} #{formatted}"
  end

  defp format_amount(_, currency), do: "#{currency} —"

  defp state_badge(state) do
    slug = state |> String.downcase() |> String.replace("_", "-")
    "badge badge-#{slug}"
  end

  defp instrument_chip("WALLET"), do: "chip chip-wallet"
  defp instrument_chip("CARD"), do: "chip chip-card"
  defp instrument_chip("BANK"), do: "chip chip-bank"
  defp instrument_chip(_), do: "chip chip-card"
end
