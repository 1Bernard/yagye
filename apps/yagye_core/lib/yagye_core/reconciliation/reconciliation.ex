defmodule YagyeCore.Reconciliation do
  @moduledoc false

  alias Ecto.Multi

  alias YagyeCore.Ledger
  alias YagyeCore.Outbox

  alias YagyeCore.Reconciliation.Schemas.{
    AdjustmentApproval,
    ProviderReportLine,
    ProviderSettlementReport,
    ReconciliationBreak,
    ReconciliationRun
  }

  alias YagyeCore.Repo

  import Ecto.Query

  # ── Public API ───────────────────────────────────────────────────────────────

  def list_breaks(merchant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    breaks =
      from(b in ReconciliationBreak,
        where: b.merchant_id == ^merchant_id,
        order_by: [desc: b.inserted_at],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {:ok, breaks}
  end

  def list_runs(merchant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    runs =
      from(r in ReconciliationRun,
        where: r.merchant_id == ^merchant_id,
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {:ok, runs}
  end

  # ── Report ingestion ─────────────────────────────────────────────────────────

  @doc """
  Ingests a provider settlement report payload.

  Idempotent on (provider_id, mode, report_date, checksum) — re-delivering the
  same file is a no-op. A different file for the same date (amended report) creates
  a new row. Bad lines are quarantined; the run proceeds with the remaining lines.

  Returns `{:ok, report}` or `{:error, {:already_ingested, existing_report}}`.
  """
  def ingest_report(provider_id, payload) do
    Multi.new()
    |> Multi.run(:idempotency, fn _repo, _changes ->
      check_idempotency(provider_id, payload)
    end)
    |> Multi.insert(
      :report,
      ProviderSettlementReport.changeset(%ProviderSettlementReport{}, %{
        provider_id: provider_id,
        mode: payload.mode,
        report_date: payload.report_date,
        source: payload.source,
        raw_uri: payload.raw_uri,
        checksum: payload.checksum,
        line_count: payload.line_count,
        reported_total: payload.reported_total,
        currency: payload.currency,
        ingested_at: DateTime.utc_now()
      })
    )
    |> Multi.run(:lines, fn repo, %{report: report} ->
      results = insert_lines(repo, report.id, payload.lines)
      {:ok, results}
    end)
    |> Multi.insert(:outbox, fn %{report: report, lines: lines} ->
      Outbox.build_changeset(report, "reconciliation.report.ingested", %{
        report_id: report.id,
        provider_id: report.provider_id,
        mode: report.mode,
        report_date: report.report_date,
        line_count: lines.ingested,
        quarantined_count: lines.quarantined,
        reported_total: report.reported_total,
        currency: report.currency
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{report: report}} ->
        {:ok, report}

      {:error, :idempotency, {:already_ingested, existing}, _} ->
        {:error, {:already_ingested, existing}}

      {:error, _step, %Ecto.Changeset{} = cs, _} ->
        {:error, cs}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  # ── Run lifecycle ─────────────────────────────────────────────────────────────

  @doc """
  Creates a reconciliation run and enqueues the matching worker.

  `opts` accepts: `provider_id`, `merchant_id`, `currency`.
  """
  def start_run(kind, mode, scope_from, scope_to, opts \\ []) do
    attrs = %{
      kind: kind,
      mode: mode,
      scope_from: scope_from,
      scope_to: scope_to,
      provider_id: Keyword.get(opts, :provider_id),
      merchant_id: Keyword.get(opts, :merchant_id),
      currency: Keyword.get(opts, :currency)
    }

    Multi.new()
    |> Multi.insert(:run, ReconciliationRun.changeset(%ReconciliationRun{}, attrs))
    |> Multi.run(:job, fn _repo, %{run: run} ->
      alias YagyeCore.Reconciliation.Workers.ReconciliationRunWorker

      {:ok, ReconciliationRunWorker.new(%{run_id: run.id}) |> Oban.insert!()}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{run: run}} -> {:ok, run}
      {:error, _step, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  # ── Break management ──────────────────────────────────────────────────────────

  @doc """
  Returns a break by its public_id, or `{:error, :not_found}`.
  """
  def get_break(public_id) do
    case Repo.get_by(ReconciliationBreak, public_id: public_id) do
      nil -> {:error, :not_found}
      break -> {:ok, break}
    end
  end

  @doc """
  Transitions a break's classification and/or state.
  """
  def classify_break(public_id, classification, attrs \\ %{}) do
    with {:ok, break} <- get_break(public_id) do
      changes = Map.merge(attrs, %{classification: classification, state: "triaged"})

      break
      |> ReconciliationBreak.changeset(changes)
      |> Repo.update()
    end
  end

  @doc """
  Proposes a ledger adjustment for a break. Subject to SoD: the approver
  cannot be the same as the proposer.
  """
  def propose_adjustment(break_public_id, proposed_by, proposed_action) do
    with {:ok, break} <- get_break(break_public_id) do
      %AdjustmentApproval{}
      |> AdjustmentApproval.propose_changeset(%{
        break_id: break.id,
        proposed_by: proposed_by,
        proposed_action: proposed_action
      })
      |> Repo.insert()
    end
  end

  @doc """
  Approves an adjustment proposal and atomically posts the correcting ledger
  entry. Returns `{:error, :sod_violation}` if approver == proposer.
  """
  def approve_adjustment(approval_id, approved_by) do
    with {:ok, approval} <- fetch_pending_approval(approval_id) do
      Multi.new()
      |> Multi.update(:approval, AdjustmentApproval.approve_changeset(approval, approved_by))
      |> Multi.run(:entry, fn _repo, %{approval: approval} ->
        post_correcting_entry(approval)
      end)
      |> Multi.run(:resolve, fn _repo, %{entry: entry, approval: approval} ->
        resolve_break_after_approval(approval.break_id, entry.id, approval)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{approval: approval}} ->
          {:ok, approval}

        {:error, :approval, %Ecto.Changeset{errors: [approved_by: _]}, _} ->
          {:error, :sod_violation}

        {:error, _step, %Ecto.Changeset{} = cs, _} ->
          {:error, cs}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Rejects an adjustment proposal.
  """
  def reject_adjustment(approval_id, reason) do
    with {:ok, approval} <- fetch_pending_approval(approval_id) do
      approval
      |> AdjustmentApproval.reject_changeset(reason)
      |> Repo.update()
    end
  end

  # ── Internal helpers ──────────────────────────────────────────────────────────

  defp check_idempotency(provider_id, payload) do
    case Repo.get_by(ProviderSettlementReport,
           provider_id: provider_id,
           mode: payload.mode,
           report_date: payload.report_date,
           checksum: payload.checksum
         ) do
      nil -> {:ok, :new}
      existing -> {:error, {:already_ingested, existing}}
    end
  end

  defp insert_lines(repo, report_id, lines) do
    Enum.reduce(lines, %{ingested: 0, quarantined: 0}, fn line_attrs, acc ->
      cs =
        ProviderReportLine.changeset(
          %ProviderReportLine{},
          Map.put(line_attrs, :report_id, report_id)
        )

      case repo.insert(cs) do
        {:ok, _line} ->
          %{acc | ingested: acc.ingested + 1}

        {:error, _cs} ->
          quarantine_cs =
            ProviderReportLine.quarantine_changeset(
              report_id,
              line_attrs[:line_number] || line_attrs["line_number"],
              line_attrs[:raw] || line_attrs["raw"] || %{}
            )

          repo.insert!(quarantine_cs)
          %{acc | quarantined: acc.quarantined + 1}
      end
    end)
  end

  defp fetch_pending_approval(approval_id) do
    case Repo.get(AdjustmentApproval, approval_id) do
      nil -> {:error, :not_found}
      %AdjustmentApproval{approved_by: nil, rejected_reason: nil} = a -> {:ok, a}
      %AdjustmentApproval{} -> {:error, :already_decided}
    end
  end

  defp post_correcting_entry(approval) do
    action = approval.proposed_action
    break = Repo.get!(ReconciliationBreak, approval.break_id)

    Ledger.post_correction(break, %{
      amount: action["amount"],
      direction: action["direction"] || "credit_merchant"
    })
  end

  defp resolve_break_after_approval(break_id, entry_id, approval) do
    break = Repo.get!(ReconciliationBreak, break_id)
    action = approval.proposed_action

    break
    |> ReconciliationBreak.resolve_changeset(
      entry_id,
      action["resolution_code"] || "adjusted",
      action["resolution_note"]
    )
    |> Repo.update()
  end
end
