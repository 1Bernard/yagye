defmodule YagyeCore.DataLake.Workers.DataLakeIngestionWorker do
  @moduledoc false

  # Polls outbox_messages and writes raw event envelopes as NDJSON to the
  # Bronze S3 bucket (Floci in dev, real AWS in prod).
  #
  # Design choices
  # ──────────────
  # • Time-window query (not a published_at watermark) — the worker is
  #   completely independent of OutboxRelayWorker. No shared lock, no
  #   coordination. It reads everything in the last @lookback_seconds window
  #   and writes it all. Bronze may receive duplicates.
  #
  # • Idempotent at Silver — Silver ETL deduplicates on event_id, so
  #   Bronze duplicates are harmless. This makes the ingestion worker
  #   safe to re-run for backfills.
  #
  # • Groups by {date, event_prefix} — one NDJSON file per group per run,
  #   named with a microsecond timestamp so runs never overwrite each other.
  #   DuckDB reads all files in a partition via a glob.
  #
  # • @lookback_seconds is intentionally larger than the cron interval (60s)
  #   to avoid dropping events that arrive just before the tick.

  use Oban.Worker, queue: :data_lake, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.DataLake.S3Writer
  alias YagyeCore.DataLake.SchemaRegistry
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Repo

  @lookback_seconds 150

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    since = DateTime.add(DateTime.utc_now(), -@lookback_seconds, :second)
    {valid, rejected} = fetch_messages(since) |> classify_messages()

    result = flush_valid(valid)
    flush_rejected(rejected)
    result
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp classify_messages(messages) do
    Enum.reduce(messages, {[], []}, fn msg, {valid_acc, rejected_acc} ->
      case SchemaRegistry.validate(msg.envelope) do
        :ok ->
          {[msg | valid_acc], rejected_acc}

        {:error, {_family, errors}} ->
          Logger.warning("data_lake.envelope_rejected",
            event_type: msg.event_type,
            error_count: length(errors)
          )

          {valid_acc, [{msg, errors} | rejected_acc]}

        {:error, reason} ->
          Logger.warning("data_lake.envelope_rejected",
            event_type: msg.event_type,
            reason: inspect(reason)
          )

          {valid_acc, [{msg, [inspect(reason)]} | rejected_acc]}
      end
    end)
  end

  defp flush_valid(messages) do
    messages
    |> Enum.group_by(&partition_key/1)
    |> Enum.reduce(:ok, fn {{date, prefix}, group}, acc ->
      case S3Writer.write(prefix, date, Enum.map(group, & &1.envelope)) do
        :ok -> acc
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp flush_rejected(rejected_pairs) do
    rejected_pairs
    |> Enum.group_by(fn {msg, _errors} -> partition_key(msg) end)
    |> Enum.reduce(:ok, fn {{date, prefix}, group}, acc ->
      envelopes =
        Enum.map(group, fn {msg, errors} ->
          Map.put(msg.envelope, "_rejection", %{
            "errors" => format_errors(errors),
            "rejected_at" => DateTime.to_iso8601(DateTime.utc_now())
          })
        end)

      case S3Writer.write_rejected(prefix, date, envelopes) do
        :ok -> acc
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp fetch_messages(since) do
    from(m in OutboxMessage,
      where: m.occurred_at >= ^since,
      order_by: [asc: m.id],
      select: [:id, :event_type, :occurred_at, :envelope]
    )
    |> Repo.all()
  end

  defp partition_key(%OutboxMessage{occurred_at: occurred_at, event_type: event_type}) do
    {DateTime.to_date(occurred_at), event_prefix(event_type)}
  end

  defp event_prefix(event_type), do: event_type |> String.split(".") |> List.first()

  defp format_errors(errors) do
    Enum.map(errors, fn
      {description, path} -> "#{path}: #{description}"
      error when is_binary(error) -> error
    end)
  end
end
