defmodule Simulator.Web.Live.ScenarioLive do
  use Phoenix.LiveView, layout: {Simulator.Web.Layouts, :admin}

  import Ecto.Query

  alias Simulator.Repo
  alias Simulator.Scenarios
  alias Simulator.Scenarios.Schemas.Scenario

  @refresh_interval 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval, self(), :refresh)

    {:ok,
     socket
     |> assign(:scenarios, Scenarios.list())
     |> assign(:editing_id, nil)
     |> assign(:changeset, nil)
     |> assign(:recent_outcomes, recent_outcomes())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     socket
     |> assign(:recent_outcomes, recent_outcomes())
     |> assign(:scenarios, Scenarios.list())}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    scenario = Repo.get!(Scenario, id)
    changeset = Scenario.changeset(scenario, %{})
    {:noreply, assign(socket, editing_id: id, changeset: changeset)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, changeset: nil)}
  end

  @impl true
  def handle_event("save", %{"scenario" => params}, socket) do
    scenario = Repo.get!(Scenario, socket.assigns.editing_id)

    case scenario |> Scenario.changeset(params) |> Repo.update() do
      {:ok, _scenario} ->
        {:noreply,
         socket
         |> assign(:scenarios, Scenarios.list())
         |> assign(:editing_id, nil)
         |> assign(:changeset, nil)
         |> put_flash(:info, "Scenario updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("set_default", %{"id" => id}, socket) do
    Repo.transaction(fn ->
      Repo.update_all(Scenario, set: [is_default: false])

      Repo.get!(Scenario, id)
      |> Scenario.changeset(%{is_default: true})
      |> Repo.update!()
    end)

    {:noreply,
     socket
     |> assign(:scenarios, Scenarios.list())
     |> put_flash(:info, "Default scenario updated.")}
  end

  @impl true
  def handle_event("validate", %{"scenario" => params}, socket) do
    scenario = Repo.get!(Scenario, socket.assigns.editing_id)
    changeset = scenario |> Scenario.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page">
      <header class="page-header">
        <h1>Scenario Control Plane</h1>
        <p class="subtitle">
          Edit failure rates live — changes take effect on the next charge.
          No restart required.
        </p>
      </header>

      <.flash_group flash={@flash} />

      <section class="outcomes-panel">
        <h2>Live Outcomes <span class="refresh-note">(refreshes every 3s)</span></h2>
        <div class="outcome-bars">
          <.outcome_bar label="AUTHORISED" count={@recent_outcomes.authorised} color="#22c55e" />
          <.outcome_bar label="DECLINED" count={@recent_outcomes.declined} color="#ef4444" />
          <.outcome_bar label="PENDING" count={@recent_outcomes.pending} color="#f59e0b" />
        </div>
        <p class="outcome-total">Last 100 charges</p>
      </section>

      <section class="scenarios-list">
        <h2>Scenarios</h2>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Success</th>
              <th>Decline</th>
              <th>Timeout</th>
              <th>Error</th>
              <th>p50 ms</th>
              <th>p95 ms</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <%= for s <- @scenarios do %>
              <tr class={if s.is_default, do: "row-default", else: ""}>
                <td>
                  {s.name}
                  <%= if s.is_default do %>
                    <span class="badge-default">DEFAULT</span>
                  <% end %>
                </td>
                <td>{format_rate(s.success_rate)}</td>
                <td>{format_rate(s.decline_rate)}</td>
                <td>{format_rate(s.timeout_rate)}</td>
                <td>{format_rate(s.provider_error_rate)}</td>
                <td>{s.latency_p50_ms}</td>
                <td>{s.latency_p95_ms}</td>
                <td class="actions">
                  <button phx-click="edit" phx-value-id={s.id} class="btn-edit">Edit</button>
                  <%= unless s.is_default do %>
                    <button phx-click="set_default" phx-value-id={s.id} class="btn-default">
                      Set default
                    </button>
                  <% end %>
                </td>
              </tr>
              <%= if @editing_id == s.id do %>
                <tr class="edit-row">
                  <td colspan="8">
                    <.edit_form changeset={@changeset} scenario={s} />
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  attr :changeset, :any, required: true
  attr :scenario, :any, required: true

  defp edit_form(assigns) do
    ~H"""
    <.form :let={f} for={@changeset} phx-change="validate" phx-submit="save" class="scenario-form">
      <div class="form-grid">
        <.rate_field form={f} field={:success_rate} label="Success rate" />
        <.rate_field form={f} field={:decline_rate} label="Decline rate" />
        <.rate_field form={f} field={:timeout_rate} label="Timeout rate" />
        <.rate_field form={f} field={:provider_error_rate} label="Provider error rate" />
        <.int_field form={f} field={:latency_p50_ms} label="p50 latency (ms)" />
        <.int_field form={f} field={:latency_p95_ms} label="p95 latency (ms)" />
        <.int_field form={f} field={:latency_p99_ms} label="p99 latency (ms)" />
        <.int_field form={f} field={:auth_validity_hours} label="Auth validity (hours)" />
        <.int_field form={f} field={:webhook_delay_max_ms} label="Max webhook delay (ms)" />
        <.rate_field form={f} field={:webhook_drop_rate} label="Webhook drop rate" />
        <.rate_field form={f} field={:duplicate_webhook_rate} label="Duplicate webhook rate" />
        <.rate_field form={f} field={:out_of_order_rate} label="Out-of-order webhook rate" />
      </div>
      <div class="form-actions">
        <button type="submit" class="btn-save">Save changes</button>
        <button type="button" phx-click="cancel_edit" class="btn-cancel">Cancel</button>
      </div>
    </.form>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp rate_field(assigns) do
    ~H"""
    <div class="form-field">
      <label>{@label}</label>
      <input
        type="number"
        name={"scenario[#{@field}]"}
        value={Phoenix.HTML.Form.input_value(@form, @field)}
        step="0.001"
        min="0"
        max="1"
        class="input-rate"
      />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp int_field(assigns) do
    ~H"""
    <div class="form-field">
      <label>{@label}</label>
      <input
        type="number"
        name={"scenario[#{@field}]"}
        value={Phoenix.HTML.Form.input_value(@form, @field)}
        min="0"
        class="input-int"
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :color, :string, required: true

  defp outcome_bar(assigns) do
    ~H"""
    <div class="outcome-bar">
      <span class="outcome-label">{@label}</span>
      <div class="bar-track">
        <div class="bar-fill" style={"width: #{@count}%; background: #{@color}"}></div>
      </div>
      <span class="outcome-count">{@count}</span>
    </div>
    """
  end

  defp flash_group(assigns) do
    ~H"""
    <%= for {kind, msg} <- @flash do %>
      <div class={"flash flash-#{kind}"}>{msg}</div>
    <% end %>
    """
  end

  defp format_rate(nil), do: "—"
  defp format_rate(%Decimal{} = d), do: "#{Decimal.mult(d, 100) |> Decimal.round(1)}%"
  defp format_rate(f), do: "#{Float.round(f * 100, 1)}%"

  defp recent_outcomes do
    from(c in "gw_charges",
      select: %{state: c.state},
      order_by: [desc: c.created_at],
      limit: 100
    )
    |> Repo.all()
    |> Enum.reduce(%{authorised: 0, declined: 0, pending: 0}, fn row, acc ->
      case row.state do
        "AUTHORISED" -> Map.update!(acc, :authorised, &(&1 + 1))
        "DECLINED" -> Map.update!(acc, :declined, &(&1 + 1))
        _ -> Map.update!(acc, :pending, &(&1 + 1))
      end
    end)
  end
end
