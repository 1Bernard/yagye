defmodule YagyeCore.DataLake.SchemaRegistry do
  @moduledoc false

  # Validates Bronze event envelopes against JSON Schema files in
  # priv/schema_registry/{family}.json (one schema per event family = the prefix
  # before the first dot in event_type).
  #
  # Schemas are resolved once per family and cached in :persistent_term.
  # Validation failure routes envelopes to events/rejected/ in S3
  # (never drops silently). The Silver ETL never sees rejected envelopes.
  #
  # Schema registration to the Redpanda Schema Registry (port 8081) is done
  # separately via `mix yagye.schema_registry.register`. Local JSON files are
  # the source of truth; the registry is for schema discovery by consumers.

  require Logger

  @families ~w[payment settlement dispute reconciliation compliance merchant checkout_session payment_link webhook]

  @doc """
  Validates an EventEnvelope map (string-keyed, as stored in outbox_messages.envelope)
  against the JSON schema for its event family.

  The family is derived from the event_type prefix (e.g. "payment.succeeded" → "payment").
  Returns `:ok` or `{:error, errors}` where errors is a list of `{description, path}` tuples.
  """
  @spec validate(map()) :: :ok | {:error, term()}
  def validate(%{"event_type" => event_type} = envelope) do
    family = event_type |> String.split(".") |> List.first()
    validate(family, envelope)
  end

  def validate(envelope) do
    {:error, {:missing_event_type, envelope}}
  end

  @doc """
  Validates an envelope map against the schema for the given `family` prefix.
  Returns `:ok` or `{:error, errors}` where errors is a list of `{description, path}` tuples.
  """
  @spec validate(String.t(), map()) :: :ok | {:error, [{String.t(), String.t()}]}
  def validate(family, envelope_map) do
    case load_schema(family) do
      nil ->
        Logger.debug("data_lake.schema_registry.no_schema", family: family)
        :ok

      schema ->
        case ExJsonSchema.Validator.validate(schema, envelope_map) do
          :ok -> :ok
          {:error, errors} -> {:error, errors}
        end
    end
  end

  @doc """
  Returns the list of event families the registry covers.
  """
  @spec families() :: [String.t()]
  def families, do: @families

  @doc """
  Registers all local schemas to the Redpanda Schema Registry.
  Called by `mix yagye.schema_registry.register`.

  Accepts `plug: {Req.Test, name}` for test stubbing.
  """
  @spec register_all(keyword()) :: :ok | {:error, term()}
  def register_all(opts \\ []) do
    base_url = Keyword.get(opts, :url, "http://localhost:8081")
    req_opts = Keyword.take(opts, [:plug])

    @families
    |> Enum.reduce(:ok, fn family, acc ->
      case register_subject(family, base_url, req_opts) do
        {:ok, id} ->
          Logger.info("data_lake.schema_registry.registered", family: family, schema_id: id)
          acc

        {:error, reason} ->
          Logger.error("data_lake.schema_registry.register_failed",
            family: family,
            reason: inspect(reason)
          )

          {:error, {family, reason}}
      end
    end)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp load_schema(family) do
    key = {__MODULE__, :schema, family}

    case :persistent_term.get(key, :not_loaded) do
      :not_loaded -> fetch_and_cache(family, key)
      :missing -> nil
      schema -> schema
    end
  end

  defp fetch_and_cache(family, key) do
    path = schema_path(family)

    case File.read(path) do
      {:ok, content} ->
        schema = content |> Jason.decode!() |> ExJsonSchema.Schema.resolve()
        :persistent_term.put(key, schema)
        schema

      {:error, :enoent} ->
        :persistent_term.put(key, :missing)
        nil
    end
  end

  defp register_subject(family, base_url, req_opts) do
    raw = File.read!(schema_path(family))
    subject = "#{family}-value"
    body = Jason.encode!(%{"schemaType" => "JSON", "schema" => raw})
    url = "#{base_url}/subjects/#{subject}/versions"

    opts =
      [
        headers: [{"content-type", "application/vnd.schemaregistry.v1+json"}],
        body: body
      ] ++ req_opts

    case Req.post(url, opts) do
      {:ok, %Req.Response{status: s, body: resp}} when s in 200..299 ->
        {:ok, resp["id"]}

      {:ok, %Req.Response{status: s, body: resp}} ->
        {:error, {s, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schema_path(family) do
    Application.app_dir(:yagye_core, "priv/schema_registry/#{family}.json")
  end
end
