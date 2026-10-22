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
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Repo

  @lookback_seconds 150

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    since = DateTime.add(DateTime.utc_now(), -@lookback_seconds, :second)
    messages = fetch_messages(since)

    messages
    |> Enum.group_by(&partition_key/1)
    |> Enum.reduce(:ok, &write_partition/2)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp write_partition({{date, prefix}, group}, acc) do
    case S3Writer.write(prefix, date, Enum.map(group, & &1.envelope)) do
      :ok -> acc
      {:error, reason} -> {:error, reason}
    end
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
    date = DateTime.to_date(occurred_at)
    prefix = event_type |> String.split(".") |> List.first()
    {date, prefix}
  end
end
