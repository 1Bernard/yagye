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

  @outcome_labels %{
    approved: {"Approved", "Wallet prompt approved — charge authorised", "authorised"},
    insufficient_funds: {"Insufficient funds", "Prompt declined: insufficient funds", "declined"},
    expired: {"Expired", "No response — prompt expires after timeout", "pending"},
    not_registered: {"Not registered", "MSISDN not registered on network", "declined"},
    declined: {"Declined", "Generic customer decline", "declined"}
  }

  @impl true
  def mount(_params, _session, socket) do
    msisdn_rows =
      OutcomeEngine.fixed_msisdn_outcomes()
      |> Enum.sort_by(fn {msisdn, _} -> msisdn end)
      |> Enum.map(fn {msisdn, outcome} ->
        prefix = String.slice(msisdn, 0, 3)
        network = Map.get(@network_prefixes, prefix, "Unknown")
        {label, description, badge} = Map.get(@outcome_labels, outcome, {"#{outcome}", "", "pending"})

        %{
          msisdn: msisdn,
          network: network,
          outcome: outcome,
          label: label,
          description: description,
          badge: badge
        }
      end)

    {:ok, assign(socket, msisdn_rows: msisdn_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page">
      <header class="page-header">
        <h1>Test Data Reference</h1>
        <p class="subtitle">
          Fixed test inputs that produce deterministic outcomes regardless of scenario rates.
          Use these in your API calls or integration tests.
        </p>
      </header>

      <section>
        <h2>Mobile Money — Fixed MSISDN Outcomes</h2>
        <p style="font-size: .8rem; color: #475569; margin-bottom: 1rem;">
          Pass <code style="background:#1e293b; padding: 1px 5px; border-radius: 3px; font-size: .8rem;">msisdn</code>
          in your <code style="background:#1e293b; padding: 1px 5px; border-radius: 3px; font-size: .8rem;">POST /charges</code>
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
              <td style="font-size: .8rem; color: #64748b;">Returns "MTN Subscriber" / "TELECEL Subscriber" etc.</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section>
        <h2>Card &amp; Bank Transfer</h2>
        <p style="font-size: .8rem; color: #475569; margin-bottom: 1rem;">
          Card and bank charges are synchronous and outcome is driven by the active
          scenario's <strong style="color: #94a3b8;">decline_rate</strong> /
          <strong style="color: #94a3b8;">timeout_rate</strong> /
          <strong style="color: #94a3b8;">provider_error_rate</strong>. There are no fixed
          test card numbers yet — use <code style="background:#1e293b; padding: 1px 5px; border-radius: 3px; font-size: .8rem;">seed</code>
          in the charge request for a reproducible roll.
        </p>
        <table>
          <thead>
            <tr>
              <th>instrument_type</th>
              <th>Flow</th>
              <th>Webhook</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><code class="mono">CARD</code></td>
              <td style="font-size: .8rem; color: #64748b;">Synchronous — response contains final state</td>
              <td><span class="badge badge-voided">None</span></td>
            </tr>
            <tr>
              <td><code class="mono">BANK</code></td>
              <td style="font-size: .8rem; color: #64748b;">Synchronous — response contains final state</td>
              <td><span class="badge badge-voided">None</span></td>
            </tr>
            <tr>
              <td><code class="mono">WALLET</code></td>
              <td style="font-size: .8rem; color: #64748b;">Async — starts PENDING_AUTH, webhook delivers final state</td>
              <td><span class="badge badge-authorised">Yes</span></td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  defp network_chip("MTN"), do: "chip chip-mtn"
  defp network_chip("TELECEL"), do: "chip chip-telecel"
  defp network_chip("AIRTELTIGO"), do: "chip chip-airteltigo"
  defp network_chip(_), do: "chip chip-card"
end
