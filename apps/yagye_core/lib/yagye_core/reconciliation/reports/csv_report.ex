defmodule YagyeCore.Reconciliation.Reports.CsvReport do
  @moduledoc """
  Parses an MNO settlement report CSV into the payload shape
  `Reconciliation.ingest_report/2` expects.

  Required columns (header row is consumed and ignored):
    SETTLEMENT_DATE,LINE_NO,CHARGE_REF,LINE_TYPE,GROSS_PESEWAS,FEE_PESEWAS,NET_PESEWAS,VALUE_DATE

  Amounts are in minor units (pesewas). Rows with parse errors are rejected
  and the whole file is refused; partial ingestion is not supported here —
  the operator should fix and re-upload.
  """

  @spec parse(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :empty_file} | {:error, {:parse_error, term()}}
  def parse(provider_id, mode, csv_text, currency \\ "GHS") do
    with {:ok, lines} <- parse_lines(csv_text, currency),
         {:ok, report_date} <- extract_report_date(lines) do
      reported_total = Enum.sum(Enum.map(lines, & &1.net_amount))
      checksum = :crypto.hash(:sha256, csv_text) |> Base.encode16(case: :lower)

      {:ok,
       %{
         provider_id: provider_id,
         mode: mode,
         report_date: report_date,
         source: "mno_csv",
         raw_uri: "portal://csv_upload/#{checksum}",
         currency: currency,
         reported_total: reported_total,
         line_count: length(lines),
         checksum: checksum,
         lines: lines
       }}
    end
  end

  defp extract_report_date([first | _]), do: {:ok, first.value_date}
  defp extract_report_date([]), do: {:error, :empty_file}

  # ── Private ───────────────────────────────────────────────────────────────────

  defp parse_lines(csv_text, currency) do
    rows =
      csv_text
      |> String.trim_leading("﻿")
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case rows do
      [] ->
        {:error, :empty_file}

      [_header | data_rows] ->
        results =
          data_rows
          |> Enum.with_index(1)
          |> Enum.map(fn {row, idx} -> parse_row(row, idx, currency) end)

        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> {:ok, Enum.map(results, fn {:ok, l} -> l end)}
          error -> {:error, {:parse_error, error}}
        end
    end
  end

  # SETTLEMENT_DATE,LINE_NO,CHARGE_REF,LINE_TYPE,GROSS_PESEWAS,FEE_PESEWAS,NET_PESEWAS,VALUE_DATE
  defp parse_row(row, idx, currency) do
    parts = row |> String.split(",") |> Enum.map(&String.trim/1)

    if length(parts) < 8 do
      {:error, {:insufficient_columns, idx, row}}
    else
      [_settlement_date, line_no, charge_ref, line_type, gross, fee, net, value_date_str | _] =
        parts

      with {line_number, ""} <- Integer.parse(line_no),
           {gross_amount, ""} <- Integer.parse(gross),
           {fee_amount, ""} <- Integer.parse(fee),
           {net_amount, ""} <- Integer.parse(net),
           {:ok, value_date} <- Date.from_iso8601(value_date_str) do
        occurred_at = DateTime.new!(value_date, ~T[00:00:00], "Etc/UTC")

        {:ok,
         %{
           line_number: line_number,
           provider_reference: charge_ref,
           transaction_type: line_type,
           gross_amount: gross_amount,
           fee_amount: fee_amount,
           net_amount: net_amount,
           currency: currency,
           occurred_at: occurred_at,
           value_date: value_date,
           raw: %{
             "charge_ref" => charge_ref,
             "line_type" => line_type,
             "gross_pesewas" => gross_amount,
             "fee_pesewas" => fee_amount,
             "net_pesewas" => net_amount
           }
         }}
      else
        _ -> {:error, {:invalid_values, idx, row}}
      end
    end
  end
end
