defmodule YagyeCore.Reconciliation.Reports.PaystackReport do
  @moduledoc """
  Parses a Paystack settlement export CSV into the payload shape
  `Reconciliation.ingest_report/2` expects.

  Expected columns (case-insensitive, order-independent):
    Transaction Date, Reference, Amount, Fee, Net Amount, Status, Settlement Date

  - Reference     → provider_reference (matches attempt.idempotency_token — we send
                    `reference: attempt.idempotency_token` to Paystack on charge)
  - Amount        → gross_amount in pesewas (Paystack GHS uses minor units natively)
  - Fee           → fee_amount in pesewas
  - Net Amount    → net_amount in pesewas
  - Status        → rows not equal to "success" are skipped
  - Settlement Date (or Transaction Date) → value_date / occurred_at

  Amounts are expected in minor units (pesewas). No conversion applied.
  """

  @required_headers ~w[reference amount fee]
  @date_headers ~w[settlement_date transaction_date]

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
      |> Enum.map(&(&1 |> String.trim() |> String.downcase() |> String.replace(" ", "_")))
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
      nil -> {:ok, Enum.flat_map(results, fn {:ok, list} -> list end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_row(row, idx, col_map, currency) do
    parts = row |> String.split(",") |> Enum.map(&String.trim/1)

    status_col = col_map["status"]

    if status_col && Enum.at(parts, status_col) &&
         String.downcase(Enum.at(parts, status_col)) != "success" do
      {:ok, []}
    else
      reference = get_col(parts, col_map, "reference")
      gross_str = get_col(parts, col_map, "amount")
      fee_str = get_col(parts, col_map, "fee")
      net_str = get_col(parts, col_map, "net_amount")
      date_str = get_date_col(parts, col_map)

      with ref when is_binary(ref) and ref != "" <- reference,
           {gross, ""} <- Integer.parse(gross_str || ""),
           {fee, ""} <- Integer.parse(fee_str || ""),
           {net, ""} <- parse_net(net_str, gross, fee),
           {:ok, value_date} <- parse_date(date_str) do
        occurred_at = DateTime.new!(value_date, ~T[00:00:00], "Etc/UTC")

        {:ok,
         [
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
               "reference" => ref,
               "gross_pesewas" => gross,
               "fee_pesewas" => fee,
               "net_pesewas" => net
             }
           }
         ]}
      else
        _ -> {:error, {:parse_error, {:invalid_values, idx, row}}}
      end
    end
  end

  defp get_col(parts, col_map, key) do
    case col_map[key] do
      nil -> nil
      idx -> Enum.at(parts, idx)
    end
  end

  defp get_date_col(parts, col_map) do
    Enum.find_value(@date_headers, fn header ->
      case col_map[header] do
        nil -> nil
        idx -> Enum.at(parts, idx)
      end
    end)
  end

  defp parse_net(nil, gross, fee), do: {gross - fee, ""}
  defp parse_net("", gross, fee), do: {gross - fee, ""}
  defp parse_net(net_str, _gross, _fee), do: Integer.parse(net_str)

  defp parse_date(nil), do: {:error, :missing_date}

  defp parse_date(date_str) do
    str = String.trim(date_str)

    case Date.from_iso8601(str) do
      {:ok, _} = ok -> ok
      {:error, _} -> parse_date_fallback(str)
    end
  end

  defp parse_date_fallback(str) do
    case Regex.run(~r/^(\d{2})\/(\d{2})\/(\d{4})$/, str) do
      [_, dd, mm, yyyy] -> Date.from_iso8601("#{yyyy}-#{mm}-#{dd}")
      _ -> parse_date_iso_prefix(str)
    end
  end

  defp parse_date_iso_prefix(str) do
    case Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})/, str) do
      [_, y, m, d] -> Date.from_iso8601("#{y}-#{m}-#{d}")
      _ -> {:error, :invalid_date}
    end
  end

  defp extract_report_date([first | _]), do: {:ok, first.value_date}
  defp extract_report_date([]), do: {:error, :empty_file}
end
