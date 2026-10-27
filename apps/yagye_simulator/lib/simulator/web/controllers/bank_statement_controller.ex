defmodule Simulator.Web.Controllers.BankStatementController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Simulator.BankStatements

  @doc """
  GET /bank-statements?date=YYYY-MM-DD[&format=csv]

  Authenticated API endpoint (x-api-key). Returns a synthetic bank statement
  for the given date. JSON by default; add `format=csv` for the import CSV.
  """
  def show(conn, %{"date" => date_string} = params) do
    with {:ok, date} <- Date.from_iso8601(date_string),
         {:ok, stmt} <- BankStatements.generate_statement(date) do
      if params["format"] == "csv" do
        render_csv(conn, stmt, date_string)
      else
        render_json(conn, stmt)
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

  @doc """
  GET /admin/bank-statements/csv?date=YYYY-MM-DD

  Unauthenticated browser download — used by the admin UI download link.
  Returns the same CSV as `show` with `format=csv`, but without API key auth.
  """
  def admin_csv(conn, %{"date" => date_string}) do
    with {:ok, date} <- Date.from_iso8601(date_string),
         {:ok, stmt} <- BankStatements.generate_statement(date) do
      render_csv(conn, stmt, date_string)
    else
      {:error, :invalid_format} ->
        conn |> put_status(400) |> text("Invalid date — expected YYYY-MM-DD")

      {:error, reason} ->
        conn |> put_status(500) |> text("Generation failed: #{inspect(reason)}")
    end
  end

  def admin_csv(conn, _params) do
    conn |> put_status(400) |> text("date param required")
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp render_json(conn, stmt) do
    json(conn, %{
      statement_date: Date.to_iso8601(stmt.statement_date),
      currency: stmt.currency,
      opening_balance_minor: stmt.opening_balance_minor,
      closing_balance_minor: stmt.closing_balance_minor,
      line_count: length(stmt.lines),
      lines:
        Enum.map(stmt.lines, fn l ->
          %{
            value_date: Date.to_iso8601(l.value_date),
            narrative: l.narrative,
            amount_minor: l.amount_minor
          }
        end)
    })
  end

  defp render_csv(conn, stmt, date_string) do
    opening_ghs = format_ghs(stmt.opening_balance_minor)
    closing_ghs = format_ghs(stmt.closing_balance_minor)

    comment_header = """
    # statement_date: #{date_string}
    # currency: #{stmt.currency}
    # opening_balance: #{opening_ghs}
    # closing_balance: #{closing_ghs}
    """

    rows =
      Enum.map_join(stmt.lines, "\n", fn line ->
        "#{Date.to_iso8601(line.value_date)},#{line.narrative},#{format_ghs(line.amount_minor)}"
      end)

    body = String.trim_trailing(comment_header) <> "\n" <> rows
    filename = "bank_statement_#{date_string}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, body)
  end

  defp format_ghs(minor) do
    sign = if minor < 0, do: "-", else: ""
    abs_val = abs(minor)
    whole = div(abs_val, 100)
    cents = rem(abs_val, 100)
    "#{sign}#{whole}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end
end
