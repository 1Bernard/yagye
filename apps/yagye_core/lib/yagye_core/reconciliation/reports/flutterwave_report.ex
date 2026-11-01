defmodule YagyeCore.Reconciliation.Reports.FlutterwaveReport do
  @moduledoc """
  Parses a Flutterwave settlement export CSV into the payload shape
  `Reconciliation.ingest_report/2` expects.

  Expected columns (case-insensitive, order-independent):
    id, txRef, flwRef, amount, currency, appfee, merchantfee, settlementAmount, createdAt

  - txRef           → provider_reference (matches attempt.idempotency_token — we send
                      `tx_ref: attempt.idempotency_token` to Flutterwave; this is the
                      safer join key for reconciliation)
  - id              → stored in raw as "flw_id" for reference
  - amount          → Flutterwave uses MAJOR units (GHS cedis) — multiply by 100 → pesewas
  - appfee          → app fee, major units → multiply by 100
  - merchantfee     → merchant fee, major units → multiply by 100
  - settlementAmount → net amount in major units → multiply by 100 → pesewas
  - createdAt       → ISO 8601 datetime → occurred_at / value_date
  """

  @required_headers ~w[txref amount]

  @spec parse(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :empty_file} | {:error, {:parse_error, term()}}
  def parse(provider_id, mode, csv_text, currency \\ "GHS") do
    with {:ok, {header, data_rows}} <- split_header_and_rows(csv_text),
         {:ok, col_map} <- map_columns(header),
         {:ok, lines} <- parse_rows(data_rows, col_map, currency),
         {:ok, report_date} <- extract_report_date(lines) do
      reported_total = Enum.sum(Enum.map(lines, & &1.net_amount))
      checksum = :crypto.hash(:sha256, csv_text) |> Base.encode16(case: :lower)

      {:ok,
       %{
         provider_id: provider_id,
         mode: mode,
         report_date: report_date,
         source: "manual_upload",
         raw_uri: "portal://csv_upload/#{checksum}",
         currency: currency,
         reported_total: reported_total,
         line_count: length(lines),
         checksum: checksum,
         lines: lines
       }}
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp split_header_and_rows(csv_text) do
    rows =
      csv_text
      |> String.trim_leading("﻿")
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

    case rows do
      [] -> {:error, :empty_file}
      [_header_only] -> {:error, :empty_file}
      [header | data] -> {:ok, {header, data}}
    end
  end

  defp map_columns(header_row) do
    headers =
      header_row
      |> String.split(",")
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
      |> Enum.with_index()

    col_map = Map.new(headers, fn {name, idx} -> {name, idx} end)

    missing = Enum.reject(@required_headers, &Map.has_key?(col_map, &1))

    if missing == [] do
      {:ok, col_map}
    else
      {:error, {:parse_error, {:missing_columns, missing}}}
    end
  end

  defp parse_rows(data_rows, col_map, currency) do
    results =
      data_rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, idx} -> parse_row(row, idx, col_map, currency) end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, line} -> line end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_row(row, idx, col_map, currency) do
    parts = row |> String.split(",") |> Enum.map(&String.trim/1)

    tx_ref = get_col(parts, col_map, "txref")
    flw_id = get_col(parts, col_map, "id")
    amount_str = get_col(parts, col_map, "amount")
    appfee_str = get_col(parts, col_map, "appfee") || "0"
    merchantfee_str = get_col(parts, col_map, "merchantfee") || "0"
    settlement_str = get_col(parts, col_map, "settlementamount")
    created_at_str = get_col(parts, col_map, "createdat")

    with ref when is_binary(ref) and ref != "" <- tx_ref,
         {:ok, gross_major} <- parse_float(amount_str),
         {:ok, appfee_major} <- parse_float(appfee_str),
         {:ok, merchantfee_major} <- parse_float(merchantfee_str),
         {:ok, net_major} <-
           parse_net_major(settlement_str, gross_major, appfee_major, merchantfee_major),
         gross <- to_pesewas(gross_major),
         fee <- to_pesewas(appfee_major + merchantfee_major),
         net <- to_pesewas(net_major),
         {:ok, occurred_at} <- parse_datetime(created_at_str),
         value_date <- DateTime.to_date(occurred_at) do
      {:ok,
       %{
         line_number: idx,
         provider_reference: ref,
         transaction_type: "collection",
         gross_amount: gross,
         fee_amount: fee,
         net_amount: net,
         currency: currency,
         occurred_at: occurred_at,
         value_date: value_date,
         raw: %{
           "flw_id" => flw_id,
           "txref" => ref,
           "gross_major" => gross_major,
           "appfee_major" => appfee_major,
           "merchantfee_major" => merchantfee_major,
           "gross_pesewas" => gross,
           "fee_pesewas" => fee,
           "net_pesewas" => net
         }
       }}
    else
      _ -> {:error, {:parse_error, {:invalid_values, idx, row}}}
    end
  end

  defp get_col(parts, col_map, key) do
    case col_map[key] do
      nil -> nil
      idx -> Enum.at(parts, idx)
    end
  end

  defp parse_float(nil), do: {:error, :missing}
  defp parse_float(""), do: {:ok, 0.0}

  defp parse_float(str) do
    case Float.parse(str) do
      {val, ""} ->
        {:ok, val}

      {val, _rest} ->
        {:ok, val}

      :error ->
        case Integer.parse(str) do
          {val, _} -> {:ok, val * 1.0}
          :error -> {:error, :invalid_float}
        end
    end
  end

  defp parse_net_major(nil, gross, appfee, merchantfee), do: {:ok, gross - appfee - merchantfee}
  defp parse_net_major("", gross, appfee, merchantfee), do: {:ok, gross - appfee - merchantfee}
  defp parse_net_major(str, _gross, _appfee, _merchantfee), do: parse_float(str)

  defp to_pesewas(major) when is_float(major), do: round(major * 100)
  defp to_pesewas(major) when is_integer(major), do: major * 100

  defp parse_datetime(nil), do: {:error, :missing_date}

  defp parse_datetime(str) do
    str = String.trim(str)

    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        {:ok, DateTime.truncate(dt, :second)}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
          {:error, _} -> {:error, {:invalid_datetime, str}}
        end
    end
  end

  defp extract_report_date([first | _]), do: {:ok, first.value_date}
  defp extract_report_date([]), do: {:error, :empty_file}
end
