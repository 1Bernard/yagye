defmodule YagyeCoreWeb.MetricsController do
  use YagyeCoreWeb, :controller

  # Prometheus scrape endpoint — unauthenticated, network-level access controls only.
  # Alloy scrapes this from within the Docker observability network.
  def index(conn, _params) do
    metrics = TelemetryMetricsPrometheus.Core.scrape(:yagye_prometheus)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end
end
