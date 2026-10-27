defmodule Simulator.Web.Live.DisbursementLive do
  use Phoenix.LiveView

  import Ecto.Query

  alias Simulator.Disbursements.Schemas.Disbursement
  alias Simulator.Repo

  @refresh_ms 2_000
  @feed_limit 60

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    {:ok, assign(socket, disbursements: load_disbursements())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, disbursements: load_disbursements())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page">
      <header class="page-header">
        <h1>
          Disbursements <span class="live-dot" title="Refreshes every 2s"></span>
        </h1>
        <p class="subtitle">
          Last 60 payout disbursements — newest first.
          Each row is a debit from Yagye's simulated float account to a merchant destination.
        </p>
      </header>

      <%= if @disbursements == [] do %>
        <div class="empty-state">
          No disbursements yet. Approve a payout request in the portal to trigger one.
        </div>
      <% else %>
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Ref</th>
              <th>Amount</th>
              <th>Dest Type</th>
              <th>Destination</th>
              <th>State</th>
              <th>Paid At</th>
            </tr>
          </thead>
          <tbody>
            <%= for d <- @disbursements do %>
              <tr class="row-default">
                <td class="time-cell">{time_ago(d.created_at)}</td>
                <td class="mono">{short_ref(d.disbursement_ref)}</td>
                <td class="amount-cell">{format_amount(d.amount_minor, d.currency)}</td>
                <td>
                  <span class={"chip chip-#{dest_chip(d.destination_type)}"}>{d.destination_type}</span>
                </td>
                <td class="mono">{d.destination_ref}</td>
                <td>{state_badge(d.state)}</td>
                <td class="time-cell">{if d.paid_at, do: format_datetime(d.paid_at), else: "—"}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  # ── Data ─────────────────────────────────────────────────────────────────────

  defp load_disbursements do
    from(d in Disbursement,
      order_by: [desc: d.created_at],
      limit: @feed_limit
    )
    |> Repo.all()
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp short_ref("DISB_" <> rest), do: "DISB_" <> String.slice(rest, 0, 8) <> "…"
  defp short_ref(ref) when is_binary(ref), do: String.slice(ref, 0, 14) <> "…"
  defp short_ref(_), do: "—"

  defp format_amount(minor, currency) when is_integer(minor) do
    major = minor / 100
    :erlang.float_to_binary(major, decimals: 2) <> " " <> currency
  end

  defp format_amount(_, currency), do: "— #{currency}"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d %b %H:%M:%S")
  end

  defp format_datetime(_), do: "—"

  defp time_ago(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(dt, "%d %b")
    end
  end

  defp time_ago(_), do: "—"

  defp dest_chip(t) when t in ["mobile_money", "MOBILE_MONEY", "momo"], do: "mtn"
  defp dest_chip(t) when t in ["bank_account", "BANK_ACCOUNT", "BANK", "bank"], do: "bank"
  defp dest_chip(_), do: "wallet"

  defp state_badge(state) do
    {label, cls} =
      case state do
        "PAID" -> {"PAID", "badge-authorised"}
        "SUBMITTED" -> {"SUBMITTED", "badge-pending"}
        "RETURNED" -> {"RETURNED", "badge-reversed"}
        "FAILED" -> {"FAILED", "badge-declined"}
        other -> {other, "badge-default"}
      end

    Phoenix.HTML.raw(~s(<span class="badge #{cls}">#{label}</span>))
  end
end
