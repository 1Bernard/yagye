defmodule YagyeCoreWeb.Controllers.Internal.ReconciliationController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  import Ecto.Query

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Reconciliation
  alias YagyeCore.Reconciliation.Reports.CsvReport
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def list_breaks(conn, %{"merchant_id" => merchant_code}) do
    with {:ok, merchant} <- resolve_merchant(merchant_code),
         {:ok, breaks} <- Reconciliation.list_breaks(merchant.id) do
      Response.ok(conn, %{
        object: "list",
        count: length(breaks),
        data: Enum.map(breaks, &break_json/1)
      })
    end
  end

  def list_all_breaks(conn, params) do
    opts = build_list_opts(params)

    with {:ok, breaks} <- Reconciliation.list_all_breaks(opts) do
      Response.ok(conn, %{
        object: "list",
        count: length(breaks),
        data: Enum.map(breaks, &break_json/1)
      })
    end
  end

  def get_break(conn, %{"id" => public_id}) do
    with {:ok, break} <- Reconciliation.get_break(public_id) do
      Response.ok(conn, break_json(break))
    end
  end

  def propose_adjustment(conn, %{"id" => public_id} = params) do
    proposed_action = %{
      "amount" => params["amount"],
      "direction" => params["direction"] || "credit_merchant",
      "resolution_code" => params["resolution_code"],
      "resolution_note" => params["resolution_note"]
    }

    with {:ok, approval} <-
           Reconciliation.propose_adjustment(public_id, params["proposed_by"], proposed_action) do
      Response.ok(conn, %{object: "adjustment_approval", id: approval.id, state: "pending"})
    end
  end

  def approve_adjustment(conn, %{"break_id" => break_id, "approved_by" => approved_by}) do
    with {:ok, approval} <- Reconciliation.approve_adjustment(break_id, approved_by) do
      Response.ok(conn, %{object: "adjustment_approval", id: approval.id, state: "approved"})
    end
  end

  def reject_adjustment(conn, %{
        "break_id" => break_id,
        "rejected_by" => rejected_by,
        "rejected_reason" => reason
      }) do
    with {:ok, approval} <- Reconciliation.reject_adjustment(break_id, rejected_by, reason) do
      Response.ok(conn, %{object: "adjustment_approval", id: approval.id, state: "rejected"})
    end
  end

  def upload_report(conn, params) do
    provider_code = params["provider_code"]
    mode = params["mode"] || "live"
    currency = params["currency"] || "GHS"
    csv_content = params["csv_content"] || ""

    with {:provider, %Provider{} = provider} <-
           {:provider, Repo.get_by(Provider, code: provider_code)},
         {:parse, {:ok, payload}} <-
           {:parse, CsvReport.parse(provider.id, mode, csv_content, currency)},
         {:ingest, {:ok, report}} <-
           {:ingest, Reconciliation.ingest_report(provider.id, payload)} do
      runs_triggered = trigger_matching_runs(provider, mode, report.report_date)

      Response.created(conn, %{
        object: "settlement_report",
        report_id: report.id,
        provider_code: provider_code,
        mode: mode,
        report_date: report.report_date,
        line_count: report.line_count,
        reported_total: report.reported_total,
        currency: report.currency,
        runs_triggered: runs_triggered
      })
    else
      {:provider, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "provider_not_found", message: "No provider with that code."}})

      {:parse, {:error, :empty_file}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "empty_file", message: "CSV file contains no data rows."}})

      {:parse, {:error, {:parse_error, detail}}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "parse_error", message: inspect(detail)}})

      {:ingest, {:error, {:already_ingested, existing}}} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: %{
            code: "duplicate_report",
            message: "Report already ingested.",
            existing_report_id: existing.id
          }
        })

      {:ingest, {:error, reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "ingest_error", message: inspect(reason)}})
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────────────

  defp trigger_matching_runs(provider, mode, report_date) do
    batches =
      from(b in SettlementBatch,
        where: b.provider_id == ^provider.id,
        where: b.mode == ^mode,
        where: fragment("?::date", b.period_start) <= ^report_date,
        where: fragment("?::date", b.period_end) >= ^report_date
      )
      |> Repo.all()

    Enum.count(batches, fn batch ->
      case Reconciliation.start_run(
             "settlement",
             batch.mode,
             batch.period_start,
             batch.period_end,
             provider_id: batch.provider_id,
             merchant_id: batch.merchant_id,
             currency: batch.currency
           ) do
        {:ok, _run} -> true
        _ -> false
      end
    end)
  end

  defp resolve_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  defp build_list_opts(params) do
    []
    |> maybe_add_provider_opt(params["provider_code"])
    |> maybe_add_merchant_opt(params["merchant_code"])
    |> maybe_add_opt(:state, params["state"])
    |> maybe_add_opt(:severity, params["severity"])
  end

  defp maybe_add_provider_opt(opts, nil), do: opts
  defp maybe_add_provider_opt(opts, ""), do: opts

  defp maybe_add_provider_opt(opts, code) do
    case Repo.get_by(Provider, code: code) do
      nil -> opts
      provider -> Keyword.put(opts, :provider_id, provider.id)
    end
  end

  defp maybe_add_merchant_opt(opts, nil), do: opts
  defp maybe_add_merchant_opt(opts, ""), do: opts

  defp maybe_add_merchant_opt(opts, public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> opts
      merchant -> Keyword.put(opts, :merchant_id, merchant.id)
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, ""), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp break_json(b) do
    %{
      object: "reconciliation_break",
      id: b.public_id,
      run_id: b.run_id,
      provider_id: b.provider_id,
      provider_code: b.provider && b.provider.code,
      provider_name: b.provider && b.provider.display_name,
      merchant_id: b.merchant_id,
      merchant_code: b.merchant && b.merchant.public_id,
      merchant_name: b.merchant && (b.merchant.trading_name || b.merchant.legal_name),
      classification: b.classification,
      severity: b.severity,
      state: b.state,
      left_ref: b.left_ref,
      right_ref: b.right_ref,
      expected_amount: b.expected_amount,
      actual_amount: b.actual_amount,
      difference: b.difference,
      currency: b.currency,
      evidence: b.evidence || %{},
      assigned_to: b.assigned_to,
      resolution_code: b.resolution_code,
      resolution_note: b.resolution_note,
      detected_at: b.detected_at,
      resolved_at: b.resolved_at,
      sla_due_at: b.sla_due_at
    }
  end
end
