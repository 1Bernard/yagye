defmodule Simulator.Web.Controllers.SettlementReportController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Simulator.Settlements

  # Ghana MoMo-style settlement file columns (minor units, pesewas)
  @csv_headers ~w[SETTLEMENT_DATE LINE_NO CHARGE_REF LINE_TYPE GROSS_PESEWAS FEE_PESEWAS NET_PESEWAS VALUE_DATE]

  @doc """
  GET /settlement-reports?date=YYYY-MM-DD[&format=csv]

  Returns the settlement file for the authenticated account on the given date.
  Idempotent. Add `format=csv` to receive a Ghana MoMo-style CSV file.
  """
  def show(conn, %{"date" => date_string} = params) do
    account = conn.assigns.current_account
    format = params["format"]

    with {:ok, date} <- Date.from_iso8601(date_string),
         {:ok, file} <- Settlements.generate_report(account, date) do
      if format == "csv" do
        render_csv(conn, file, date_string)
      else
        render_json(conn, file)
      end
    else
      {:error, :invalid_format} ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid_date", message: "date must be YYYY-MM-DD"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "generation_failed", message: inspect(reason)})
    end
  end

  def show(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "missing_date", message: "date query param required"})
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp render_json(conn, file) do
    lines =
      Enum.map(file.lines, fn line ->
        %{
          line_number: line.line_number,
          charge_ref: line.charge_ref,
          line_type: line.line_type,
          gross_minor: line.gross_minor,
          fee_minor: line.fee_minor,
          net_minor: line.net_minor,
          value_date: Date.to_iso8601(line.value_date)
        }
      end)

    json(conn, %{
      file_ref: file.file_ref,
      settlement_date: Date.to_iso8601(file.settlement_date),
      currency: file.currency,
      gross_minor: file.gross_minor,
      fee_minor: file.fee_minor,
      net_minor: file.net_minor,
      line_count: file.line_count,
      lines: lines
    })
  end

  defp render_csv(conn, file, date_string) do
    settlement_date = Date.to_iso8601(file.settlement_date)

    rows =
      Enum.map_join(file.lines, "\n", fn line ->
        [
          settlement_date,
          line.line_number,
          line.charge_ref || "",
          line.line_type,
          line.gross_minor,
          line.fee_minor,
          line.net_minor,
          Date.to_iso8601(line.value_date)
        ]
        |> Enum.map_join(",", &to_string/1)
      end)

    header = Enum.join(@csv_headers, ",")
    body = if rows == "", do: header, else: "#{header}\n#{rows}"
    filename = "settlement_#{date_string}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, body)
  end
end
