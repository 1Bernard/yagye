defmodule Simulator.MixProject do
  use Mix.Project

  def project do
    [
      app: :simulator,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      mod: {Simulator.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_live_view, "~> 1.0"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.2"},
      {:uniq, "~> 0.6.3"},
      {:oban, "~> 2.23"},
      {:req, "~> 0.5"},
      {:open_api_spex, "~> 3.21"},
      {:logger_json, "~> 7.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "format",
        "compile",
        "credo --strict",
        "sobelow --config",
        "compile --warnings-as-errors",
        "test --warnings-as-errors"
      ]
    ]
  end
end
