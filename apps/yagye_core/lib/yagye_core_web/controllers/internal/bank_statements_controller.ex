defmodule YagyeCoreWeb.Controllers.Internal.BankStatementsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.BankReconciliation
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  @doc """
  Imports a bank statement with its transaction lines.

  Expects JSON body:
    {
      "account_reference": "yagye-ghipss-001",
      "statement_date": "2026-10-01",
      "currency": "GHS",
      "mode": "live",
      "source": "ghipss",
      "opening_balance": 150000,
      "closing_balance": 980000,
      "lines": [
        {
          "line_number": 1,
          "value_date": "2026-10-01",
          "description": "Settlement credit from MTN",
          "amount": 50000,
          "direction": "credit",
          "provider_reference": "ps_ref_123"
        }
      ]
    }
  """
  def create(conn, params) do
    statement_attrs = %{
      account_reference: params["account_reference"],
      statement_date: params["statement_date"],
      currency: params["currency"] || "GHS",
      mode: params["mode"] || "live",
      source: params["source"],
      raw_uri: params["raw_uri"],
      checksum: params["checksum"],
      opening_balance: params["opening_balance"],
      closing_balance: params["closing_balance"]
    }

    default_currency = params["currency"] || "GHS"
    lines = Enum.map(params["lines"] || [], &normalize_line(&1, default_currency))

    case BankReconciliation.ingest_statement(statement_attrs, lines) do
      {:ok, %{statement: stmt, line_count: count}} ->
        Response.created(conn, %{
          object: "bank_statement",
          id: stmt.id,
          account_reference: stmt.account_reference,
          statement_date: stmt.statement_date,
          currency: stmt.currency,
          line_count: count,
          ingested_at: stmt.ingested_at
        })

      {:error, :duplicate_statement} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: %{code: "duplicate_statement", message: "Statement already ingested."}})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "validation_error", errors: format_errors(cs)}})
    end
  end

  def index(conn, params) do
    ref = params["account_reference"]
    limit = min(String.to_integer(params["limit"] || "50"), 200)
    statements = BankReconciliation.list_statements(ref, limit: limit)

    Response.ok(conn, %{
      object: "list",
      count: length(statements),
      data: Enum.map(statements, &statement_json/1)
    })
  end

  def show(conn, %{"id" => id}) do
    with {:ok, stmt} <- BankReconciliation.get_statement(id) do
      summary = BankReconciliation.line_match_summary(stmt)
      lines = BankReconciliation.list_lines(stmt)

      resp =
        stmt
        |> statement_json()
        |> Map.merge(%{
          match_summary: summary,
          lines: Enum.map(lines, &line_json/1)
        })

      Response.ok(conn, resp)
    end
  end

  defp statement_json(stmt) do
    %{
      object: "bank_statement",
      id: stmt.id,
      account_reference: stmt.account_reference,
      statement_date: stmt.statement_date,
      currency: stmt.currency,
      mode: stmt.mode,
      source: stmt.source,
      opening_balance: stmt.opening_balance,
      closing_balance: stmt.closing_balance,
      ingested_at: stmt.ingested_at
    }
  end

  defp line_json(line) do
    %{
      id: line.id,
      line_number: line.line_number,
      value_date: line.value_date,
      amount: line.amount,
      currency: line.currency,
      narrative: line.narrative,
      bank_reference: line.bank_reference,
      counterparty: line.counterparty,
      match_state: line.match_state,
      inserted_at: line.inserted_at
    }
  end

  defp normalize_line(l, default_currency) do
    %{
      line_number: l["line_number"],
      value_date: l["value_date"],
      narrative: l["narrative"] || l["description"],
      amount: l["amount"],
      currency: l["currency"] || default_currency,
      bank_reference: l["bank_reference"],
      counterparty: l["counterparty"]
    }
  end
end
