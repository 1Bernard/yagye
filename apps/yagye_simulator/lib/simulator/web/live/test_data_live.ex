defmodule Simulator.Web.Live.TestDataLive do
  use Phoenix.LiveView

  alias Simulator.OutcomeEngine

  @network_prefixes %{
    "024" => "MTN",
    "054" => "MTN",
    "055" => "MTN",
    "059" => "MTN",
    "020" => "TELECEL",
    "050" => "TELECEL",
    "026" => "AIRTELTIGO",
    "027" => "AIRTELTIGO",
    "056" => "AIRTELTIGO",
    "057" => "AIRTELTIGO"
  }

  @wallet_outcome_labels %{
    approved: {"Approved", "Wallet prompt approved — charge authorised", "authorised"},
    insufficient_funds: {"Insufficient funds", "Prompt declined: insufficient funds", "declined"},
    expired: {"Expired", "No response — prompt expires after timeout", "pending"},
    not_registered: {"Not registered", "MSISDN not registered on network", "declined"},
    declined: {"Declined", "Generic customer decline", "declined"},
    approved_no_webhook:
      {"Approved (no webhook)",
       "Charge resolves but webhook is suppressed — tests PaymentStatusCheckWorker polling",
       "pending"},
    pending_no_webhook:
      {"Stays pending (no webhook)",
       "Charge stays PENDING_AUTH forever — exercises PaymentTimeoutWorker deadline", "pending"}
  }

  @card_names %{
    "4242424242424242" => "Visa — success",
    "4000000000000002" => "Generic decline",
    "4000000000009995" => "Insufficient funds",
    "4000000000000069" => "Expired card",
    "4000000000000119" => "Network timeout",
    "4000000000000259" => "Provider error"
  }

  @impl true
  def mount(_params, _session, socket) do
    msisdn_rows = build_msisdn_rows()
    card_rows = build_card_rows()
    {:ok, assign(socket, msisdn_rows: msisdn_rows, card_rows: card_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page">
      <header class="page-header">
        <h1>Test Data Reference</h1>
        <p class="subtitle">
          Fixed test inputs that produce deterministic outcomes regardless of scenario rates.
          Use these in your API calls, integration tests, or the
          <a href="/admin/simulate" style="color: #0ea5e9;">Live Simulation</a>
          page.
        </p>
      </header>

      <section>
        <h2>Mobile Money — Fixed MSISDN Outcomes</h2>
        <p style="font-size: .8rem; color: #475569; margin-bottom: 1rem;">
          Pass <code class="icode">msisdn</code>
          in your <code class="icode">POST /charges</code>
          body. Any other MSISDN falls back to the active scenario's rate distribution.
        </p>
        <table>
          <thead>
            <tr>
              <th>MSISDN</th>
              <th>Network</th>
              <th>Outcome</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @msisdn_rows do %>
              <tr>
                <td><code class="mono">{row.msisdn}</code></td>
                <td><span class={network_chip(row.network)}>{row.network}</span></td>
                <td><span class={"badge badge-#{row.badge}"}>{row.label}</span></td>
                <td style="font-size: .8rem; color: #64748b;">{row.description}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </section>

      <section>
        <h2>Card — Fixed Card Number Outcomes</h2>
        <p style="font-size: .8rem; color: #475569; margin-bottom: 1rem;">
          Pass <code class="icode">card_number</code>
          in your <code class="icode">POST /charges</code>
          body (spaces stripped automatically).
          Any other card number falls back to the active scenario's rate distribution.
          Card charges are <strong style="color: #94a3b8;">synchronous</strong>
          — the final
          state is in the response body.
        </p>
        <table>
          <thead>
            <tr>
              <th>Card Number</th>
              <th>Description</th>
              <th>Outcome</th>
              <th>Decline Code</th>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @card_rows do %>
              <tr>
                <td><code class="mono">{row.formatted}</code></td>
                <td style="font-size: .8rem; color: #64748b;">{row.name}</td>
                <td><span class={"badge badge-#{row.badge}"}>{row.label}</span></td>
                <td>
                  <%= if row.decline_code do %>
                    <span class="decline-code">{row.decline_code}</span>
                  <% else %>
                    <span style="color: #334155">—</span>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </section>

      <section>
        <h2>Name Enquiry Rules</h2>
        <p style="font-size: .8rem; color: #475569; margin-bottom: 1rem;">
          Called automatically before a wallet charge. Controls whether an account name is returned.
        </p>
        <table>
          <thead>
            <tr>
              <th>Condition</th>
              <th>Outcome</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><code class="mono">msisdn == "0241000004"</code></td>
              <td><span class="badge badge-declined">Not found</span></td>
              <td style="font-size: .8rem; color: #64748b;">Fixed: always returns NOT_FOUND</td>
            </tr>
            <tr>
              <td><code class="mono">msisdn ends with "0"</code></td>
              <td><span class="badge badge-declined">Not found</span></td>
              <td style="font-size: .8rem; color: #64748b;">Heuristic: any MSISDN ending in 0</td>
            </tr>
            <tr>
              <td>All others</td>
              <td><span class="badge badge-authorised">Found</span></td>
              <td style="font-size: .8rem; color: #64748b;">
                Returns "MTN Subscriber" / "TELECEL Subscriber" etc.
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section>
        <h2>Instrument Flow Summary</h2>
        <table>
          <thead>
            <tr>
              <th>instrument_type</th>
              <th>Resolution</th>
              <th>Fixed Inputs</th>
              <th>Webhook</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><code class="mono">CARD</code></td>
              <td style="font-size: .8rem; color: #64748b;">
                Synchronous — final state in response
              </td>
              <td style="font-size: .8rem; color: #64748b;">Fixed card numbers (above)</td>
              <td><span class="badge badge-voided">None</span></td>
            </tr>
            <tr>
              <td><code class="mono">BANK</code></td>
              <td style="font-size: .8rem; color: #64748b;">
                Synchronous — final state in response
              </td>
              <td style="font-size: .8rem; color: #64748b;">None — scenario rates only</td>
              <td><span class="badge badge-voided">None</span></td>
            </tr>
            <tr>
              <td><code class="mono">WALLET</code></td>
              <td style="font-size: .8rem; color: #64748b;">
                Async — starts PENDING_AUTH, webhook delivers final state
              </td>
              <td style="font-size: .8rem; color: #64748b;">Fixed MSISDNs (above)</td>
              <td><span class="badge badge-authorised">Yes</span></td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  # ── Data builders ─────────────────────────────────────────────────────────────

  defp build_msisdn_rows do
    OutcomeEngine.fixed_msisdn_outcomes()
    |> Enum.sort_by(fn {msisdn, _} -> msisdn end)
    |> Enum.map(fn {msisdn, outcome} ->
      prefix = String.slice(msisdn, 0, 3)
      network = Map.get(@network_prefixes, prefix, "Unknown")

      {label, description, badge} =
        Map.get(@wallet_outcome_labels, outcome, {"#{outcome}", "", "pending"})

      %{
        msisdn: msisdn,
        network: network,
        outcome: outcome,
        label: label,
        description: description,
        badge: badge
      }
    end)
  end

  defp build_card_rows do
    OutcomeEngine.fixed_card_outcomes()
    |> Enum.sort_by(fn {number, _} -> number end)
    |> Enum.map(fn {number, outcome} ->
      {label, badge, decline_code} = card_outcome_display(outcome)
      name = Map.get(@card_names, number, number)
      formatted = format_card_number(number)
      %{formatted: formatted, name: name, label: label, badge: badge, decline_code: decline_code}
    end)
  end

  defp card_outcome_display(:authorised), do: {"AUTHORISED", "authorised", nil}
  defp card_outcome_display(:timeout), do: {"PENDING_AUTH", "pending", nil}
  defp card_outcome_display(:provider_error), do: {"PENDING_AUTH", "pending", nil}
  defp card_outcome_display({:declined, code}), do: {"DECLINED", "declined", code}
  defp card_outcome_display(_), do: {"DECLINED", "declined", nil}

  defp format_card_number(number) do
    number
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  # ── CSS helpers ───────────────────────────────────────────────────────────────

  defp network_chip("MTN"), do: "chip chip-mtn"
  defp network_chip("TELECEL"), do: "chip chip-telecel"
  defp network_chip("AIRTELTIGO"), do: "chip chip-airteltigo"
  defp network_chip(_), do: "chip chip-card"
end
