defmodule Simulator.Web.Controllers.SettlementReportController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Simulator.Settlements

  @doc """
  GET /settlement-reports?date=YYYY-MM-DD

  Returns the settlement file for the authenticated account on the given date,
  generating it if it has not been generated yet. Idempotent.
  """
  def show(conn, %{"date" => date_string}) do
    account = conn.assigns.current_account

    with {:ok, date} <- Date.from_iso8601(date_string),
         {:ok, file} <- Settlements.generate_report(account, date) do
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
end
