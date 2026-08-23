defmodule Simulator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:simulator, :repo])
    OpentelemetryOban.setup()

    children = [
      Simulator.Repo,
      {Oban, Application.fetch_env!(:simulator, Oban)},
      Simulator.Web.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Simulator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
