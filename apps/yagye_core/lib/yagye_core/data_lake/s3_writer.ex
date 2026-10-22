defmodule YagyeCore.DataLake.S3Writer do
  @moduledoc false

  # Writes NDJSON files to the Bronze S3 bucket (Floci in dev, real AWS in prod).
  #
  # Bronze is intentionally raw — no schema enforcement, no deduplication.
  # The Silver ETL (yagye_data Python) is responsible for validation,
  # deduplication by event_id, and Parquet conversion.
  #
  # Key pattern:
  #   events/dt=YYYY-MM-DD/<event_prefix>_<microseconds>.ndjson
  #
  # The dt= prefix enables DuckDB hive partitioning for efficient date-range
  # scans in Silver without reading the whole Bronze bucket.

  require Logger

  @spec write(String.t(), Date.t(), [map()]) :: :ok | {:error, term()}
  def write(event_prefix, date, rows) when rows != [] do
    bucket = bronze_bucket()
    key = build_key(event_prefix, date)
    body = encode_ndjson(rows)

    case ExAws.S3.put_object(bucket, key, body, content_type: "application/x-ndjson")
         |> ExAws.request() do
      {:ok, _} ->
        Logger.debug("data_lake.s3.written",
          bucket: bucket,
          key: key,
          row_count: length(rows),
          bytes: byte_size(body)
        )

        :ok

      {:error, reason} ->
        Logger.warning("data_lake.s3.write_failed", key: key, reason: inspect(reason))
        {:error, reason}
    end
  end

  def write(_event_prefix, _date, []), do: :ok

  # ── Private ──────────────────────────────────────────────────────────────────

  defp bronze_bucket do
    Application.get_env(:yagye_core, :data_lake, [])
    |> Keyword.get(:bronze_bucket, "yagye-lake-raw")
  end

  defp build_key(event_prefix, %Date{} = date) do
    ts = System.os_time(:microsecond)
    ds = Date.to_iso8601(date)
    "events/dt=#{ds}/#{event_prefix}_#{ts}.ndjson"
  end

  defp encode_ndjson(rows) do
    Enum.map_join(rows, "\n", &Jason.encode!/1)
  end
end
