defmodule Simulator.Release do
  @moduledoc false

  # Used by Ecto.Migrator in production releases where Mix is not available.
  # Called from docker-compose and deployment entrypoints:
  #
  #   /app/bin/simulator eval "Simulator.Release.migrate()"

  @app :simulator

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
end
