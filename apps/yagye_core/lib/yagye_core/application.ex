defmodule YagyeCore.Application do
  @moduledoc false

  use Boundary, top_level?: true, deps: [YagyeCore, YagyeCoreWeb]
  use Application

  @impl true
  def start(_type, _args) do
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:yagye_core, :repo])
    OpentelemetryOban.setup()

    children = [
      YagyeCoreWeb.Telemetry,
      YagyeCore.Repo,
      YagyeCore.Shared.RateLimiter,
      {DNSCluster, query: Application.get_env(:yagye_core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: YagyeCore.PubSub},
      {Oban, Application.fetch_env!(:yagye_core, Oban)},
      YagyeCoreWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YagyeCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YagyeCoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
