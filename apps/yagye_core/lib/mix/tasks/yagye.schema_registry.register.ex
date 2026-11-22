defmodule Mix.Tasks.Yagye.SchemaRegistry.Register do
  @shortdoc "Registers Bronze envelope JSON schemas to the Redpanda schema registry"

  @moduledoc """
  Registers all event-family JSON schemas from `priv/schema_registry/`
  to the Redpanda schema registry HTTP API.

  Usage:

      mix yagye.schema_registry.register

  Options:

      --url   Base URL of the schema registry (default: http://localhost:8081)

  Run this once after bringing up the Redpanda stack, and again any time
  a schema file changes. Existing schemas with the same subject are
  updated only when the schema content differs (the registry is idempotent
  for identical payloads).
  """

  use Mix.Task
  use Boundary, classify_to: YagyeCore

  alias YagyeCore.DataLake.SchemaRegistry

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [url: :string])

    Mix.Task.run("app.start")

    case SchemaRegistry.register_all(opts) do
      :ok ->
        Mix.shell().info("All schemas registered successfully.")

      {:error, {family, reason}} ->
        Mix.shell().error("Failed to register schema for #{family}: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
