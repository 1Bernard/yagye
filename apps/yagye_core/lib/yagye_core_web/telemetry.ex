defmodule YagyeCoreWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus.Core, metrics: metrics(), name: :yagye_prometheus}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # ── Phoenix ──────────────────────────────────────────────────────────────
      counter("phoenix.endpoint.stop.count",
        tags: [:status],
        tag_values: &extract_http_status/1
      ),
      distribution("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route, :status],
        tag_values: &extract_route_status/1,
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),
      counter("phoenix.router_dispatch.exception.count",
        tags: [:route, :kind]
      ),

      # ── Database ─────────────────────────────────────────────────────────────
      distribution("yagye_core.repo.query.total_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000]]
      ),
      distribution("yagye_core.repo.query.queue_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100]]
      ),

      # ── Oban jobs ────────────────────────────────────────────────────────────
      counter("oban.job.completed.count",
        tags: [:queue, :worker, :state],
        tag_values: &extract_oban_state/1
      ),
      distribution("oban.job.duration",
        tags: [:queue, :worker],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [100, 500, 1000, 5000, 15_000, 60_000, 300_000]]
      ),

      # ── Payments (business metrics for SLOs) ─────────────────────────────────
      # Emitted by YagyeCore.Payments when a payment event is recorded.
      # yagye.payment.event is dispatched as:
      #   :telemetry.execute([:yagye, :payment, :event], %{count: 1}, %{event_type: event_type, mode: mode})
      counter("yagye.payment.event.count",
        tags: [:event_type, :mode],
        event_name: [:yagye, :payment, :event]
      ),

      # ── Settlements ──────────────────────────────────────────────────────────
      # Emitted by SettlementProcessorWorker on each sweep.
      # yagye.settlement.sweep: %{batch_count: n, total_amount_minor: n}
      counter("yagye.settlement.sweep.count",
        event_name: [:yagye, :settlement, :sweep]
      ),
      sum("yagye.settlement.sweep.batch_count",
        event_name: [:yagye, :settlement, :sweep]
      ),

      # ── VM ───────────────────────────────────────────────────────────────────
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    []
  end

  defp extract_http_status(%{status: status}) when is_integer(status),
    do: %{status: div(status, 100) |> then(&"#{&1}xx")}

  defp extract_http_status(_), do: %{status: "unknown"}

  defp extract_route_status(%{route: route, status: status}) when is_integer(status),
    do: %{route: route, status: div(status, 100) |> then(&"#{&1}xx")}

  defp extract_route_status(meta), do: %{route: meta[:route] || "unknown", status: "unknown"}

  defp extract_oban_state(%{state: state} = meta),
    do: %{queue: meta[:queue] || "unknown", worker: meta[:worker] || "unknown", state: state}

  defp extract_oban_state(meta),
    do: %{queue: meta[:queue] || "unknown", worker: meta[:worker] || "unknown", state: "unknown"}
end
