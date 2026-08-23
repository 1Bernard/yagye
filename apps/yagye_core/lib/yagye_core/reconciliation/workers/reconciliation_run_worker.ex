defmodule YagyeCore.Reconciliation.Workers.ReconciliationRunWorker do
  @moduledoc false

  use Oban.Worker, queue: :reconciliation, max_attempts: 3

  require OpenTelemetry.Tracer

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  alias YagyeCore.Reconciliation.Schemas.{
    ProviderReportLine,
    ProviderSettlementReport,
    ReconciliationBreak,
    ReconciliationMatch,
    ReconciliationRun
  }

  alias YagyeCore.Repo

  @exact_confidence Decimal.new("1.000")
  @composite_confidence Decimal.new("0.850")
  @amount_window_confidence Decimal.new("0.650")

  # window for composite matching: attempt.inserted_at within ±24h of line.occurred_at
  @composite_window_seconds 86_400
  # tolerance for amount_window matching: 5%
  @amount_tolerance_bps 500
  # date window for amount_window: ±3 days
  @amount_window_seconds 259_200

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => id}}) do
    OpenTelemetry.Tracer.with_span "reconciliation.run" do
      run = Repo.get!(ReconciliationRun, id)
      reconcile(run)
    end
  end

  defp reconcile(%ReconciliationRun{state: state}) when state in ["completed", "failed"], do: :ok

  defp reconcile(%ReconciliationRun{} = run) do
    with :ok <- transition(run, "loading"),
         run <- Repo.get!(ReconciliationRun, run.id),
         left_items <- fetch_left(run),
         right_items <- fetch_right(run),
         :ok <- transition(run, "matching"),
         run <- Repo.get!(ReconciliationRun, run.id),
         {matches, breaks} <- run_strategies(run, left_items, right_items),
         :ok <- transition(run, "classifying"),
         run <- Repo.get!(ReconciliationRun, run.id),
         {:ok, _} <- persist_results(run, matches, breaks, left_items, right_items) do
      :ok
    else
      {:error, reason} ->
        mark_failed(Repo.get!(ReconciliationRun, run.id), reason)
        {:error, reason}
    end
  end

  # ── Data loading ─────────────────────────────────────────────────────────────

  defp fetch_left(%ReconciliationRun{} = run) do
    Repo.all(
      from a in PaymentAttempt,
        join: p in Payment,
        on: a.payment_id == p.id,
        where: a.provider_id == ^run.provider_id,
        where: p.mode == ^run.mode,
        where: a.state == "succeeded",
        where: a.inserted_at >= ^run.scope_from,
        where: a.inserted_at < ^run.scope_to,
        select: %{
          id: a.id,
          provider_reference: a.provider_reference,
          amount: p.amount,
          currency: p.currency,
          merchant_id: p.merchant_id,
          occurred_at: a.inserted_at
        }
    )
  end

  defp fetch_right(%ReconciliationRun{} = run) do
    Repo.all(
      from l in ProviderReportLine,
        join: r in ProviderSettlementReport,
        on: l.report_id == r.id,
        where: r.provider_id == ^run.provider_id,
        where: r.mode == ^run.mode,
        where: l.match_state == "unmatched",
        where: l.occurred_at >= ^run.scope_from,
        where: l.occurred_at < ^run.scope_to,
        select: %{
          id: l.id,
          provider_reference: l.provider_reference,
          gross_amount: l.gross_amount,
          currency: l.currency,
          occurred_at: l.occurred_at
        }
    )
  end

  # ── Matching strategies ───────────────────────────────────────────────────────

  defp run_strategies(run, left_items, right_items) do
    ul = index_by(left_items, :provider_reference)
    ur = index_by(right_items, :provider_reference)

    {exact_matches, ul, ur} = match_exact_reference(run, ul, ur)
    {composite_matches, ul, ur} = match_composite(run, ul, ur)
    {window_matches, ul, ur} = match_amount_window(run, ul, ur)

    all_matches = exact_matches ++ composite_matches ++ window_matches
    breaks = build_breaks(run, Map.values(ul), Map.values(ur))

    {all_matches, breaks}
  end

  defp match_exact_reference(run, unmatched_left, unmatched_right) do
    Enum.reduce(unmatched_left, {[], unmatched_left, unmatched_right}, fn
      {ref, _left}, acc when is_nil(ref) ->
        acc

      {ref, left}, {matches, ul, ur} ->
        case Map.fetch(ur, ref) do
          {:ok, right} ->
            match = build_match(run, "exact_reference", @exact_confidence, left, right)
            {[match | matches], Map.delete(ul, ref), Map.delete(ur, ref)}

          :error ->
            {matches, ul, ur}
        end
    end)
  end

  defp match_composite(run, unmatched_left, unmatched_right) do
    right_list = Map.values(unmatched_right)

    Enum.reduce(unmatched_left, {[], unmatched_left, unmatched_right}, fn {key, left},
                                                                          {matches, ul, ur} ->
      case find_composite_match(left, right_list) do
        nil ->
          {matches, ul, ur}

        right ->
          match = build_match(run, "composite", @composite_confidence, left, right)
          right_key = right[:provider_reference] || right.id

          {[match | matches], Map.delete(ul, key), Map.delete(ur, right_key)}
      end
    end)
  end

  defp find_composite_match(left, right_list) do
    Enum.find(right_list, fn right ->
      right[:currency] == left[:currency] &&
        right[:gross_amount] == left[:amount] &&
        within_seconds?(left[:occurred_at], right[:occurred_at], @composite_window_seconds)
    end)
  end

  defp match_amount_window(run, unmatched_left, unmatched_right) do
    right_list = Map.values(unmatched_right)

    Enum.reduce(unmatched_left, {[], unmatched_left, unmatched_right}, fn {key, left},
                                                                          {matches, ul, ur} ->
      case find_window_match(left, right_list) do
        nil ->
          {matches, ul, ur}

        right ->
          match = build_match(run, "amount_window", @amount_window_confidence, left, right)
          right_key = right[:provider_reference] || right.id

          {[match | matches], Map.delete(ul, key), Map.delete(ur, right_key)}
      end
    end)
  end

  defp find_window_match(left, right_list) do
    Enum.find(right_list, fn right ->
      right[:currency] == left[:currency] &&
        within_tolerance?(left[:amount], right[:gross_amount], @amount_tolerance_bps) &&
        within_seconds?(left[:occurred_at], right[:occurred_at], @amount_window_seconds)
    end)
  end

  # ── Break detection ───────────────────────────────────────────────────────────

  defp build_breaks(run, unmatched_left, unmatched_right) do
    left_breaks =
      Enum.map(unmatched_left, fn left ->
        %{
          run_id: run.id,
          merchant_id: left[:merchant_id],
          provider_id: run.provider_id,
          mode: run.mode,
          classification: "missing_on_right",
          severity: "high",
          left_ref: left[:provider_reference],
          expected_amount: left[:amount],
          actual_amount: 0,
          difference: left[:amount],
          currency: left[:currency],
          evidence: %{
            "left_id" => left[:id],
            "occurred_at" => DateTime.to_iso8601(left[:occurred_at] || DateTime.utc_now())
          }
        }
      end)

    right_breaks =
      Enum.map(unmatched_right, fn right ->
        %{
          run_id: run.id,
          provider_id: run.provider_id,
          mode: run.mode,
          classification: "missing_on_left",
          severity: "high",
          right_ref: right[:provider_reference],
          expected_amount: 0,
          actual_amount: right[:gross_amount],
          difference: right[:gross_amount] && -right[:gross_amount],
          currency: right[:currency],
          evidence: %{
            "right_id" => right[:id],
            "occurred_at" => right[:occurred_at] && DateTime.to_iso8601(right[:occurred_at])
          }
        }
      end)

    left_breaks ++ right_breaks
  end

  # ── Persistence ───────────────────────────────────────────────────────────────

  defp persist_results(run, matches, breaks, left_items, right_items) do
    matched_value = matches |> Enum.map(fn m -> m.amount_left || 0 end) |> Enum.sum()
    break_value = breaks |> Enum.map(fn b -> abs(b[:difference] || 0) end) |> Enum.sum()

    Multi.new()
    |> Multi.run(:matches, fn repo, _changes ->
      Enum.each(matches, fn attrs ->
        repo.insert!(ReconciliationMatch.changeset(%ReconciliationMatch{}, attrs))
      end)

      {:ok, length(matches)}
    end)
    |> Multi.run(:breaks, fn repo, _changes ->
      Enum.each(breaks, fn attrs ->
        repo.insert!(ReconciliationBreak.changeset(%ReconciliationBreak{}, attrs))
      end)

      {:ok, length(breaks)}
    end)
    |> Multi.run(:mark_lines, fn _repo, _changes ->
      matched_line_ids = matches |> Enum.flat_map(fn m -> m.right_ids end)

      Repo.update_all(
        from(l in ProviderReportLine, where: l.id in ^matched_line_ids),
        set: [match_state: "matched"]
      )

      {:ok, :done}
    end)
    |> Multi.update(:complete, fn _changes ->
      run
      |> ReconciliationRun.transition_changeset("completed")
      |> ReconciliationRun.progress_changeset(%{
        left_count: length(left_items),
        right_count: length(right_items),
        matched_count: length(matches),
        break_count: length(breaks),
        matched_value: matched_value,
        break_value: break_value
      })
    end)
    |> Multi.insert(:outbox, fn %{complete: run} ->
      Outbox.build_changeset(run, "reconciliation.run.completed", %{
        run_id: run.id,
        public_id: run.public_id,
        kind: run.kind,
        matched_count: run.matched_count,
        break_count: run.break_count,
        matched_value: run.matched_value,
        break_value: run.break_value
      })
    end)
    |> Repo.transaction()
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp build_match(run, strategy, confidence, left, right) do
    %{
      run_id: run.id,
      strategy: strategy,
      confidence: confidence,
      left_type: "payment_attempt",
      left_ids: [left[:id]],
      right_type: "provider_report_line",
      right_ids: [right[:id]],
      amount_left: left[:amount],
      amount_right: right[:gross_amount],
      currency: left[:currency],
      auto_accepted:
        Decimal.compare(confidence, ReconciliationMatch.auto_accept_threshold()) in [:gt, :eq]
    }
  end

  defp index_by(list, key) do
    list
    |> Enum.filter(fn item -> not is_nil(item[key]) end)
    |> Map.new(fn item -> {item[key], item} end)
  end

  defp within_seconds?(nil, _right, _window), do: false
  defp within_seconds?(_left, nil, _window), do: false

  defp within_seconds?(left_dt, right_dt, window) do
    abs(DateTime.diff(left_dt, right_dt, :second)) <= window
  end

  defp within_tolerance?(_left, nil, _bps), do: false
  defp within_tolerance?(nil, _right, _bps), do: false

  defp within_tolerance?(left, right, bps) do
    diff = abs(left - right)
    diff * 10_000 <= left * bps
  end

  defp transition(run, new_state) do
    run
    |> ReconciliationRun.transition_changeset(new_state)
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_failed(run, _reason) do
    run
    |> ReconciliationRun.transition_changeset("failed")
    |> Repo.update()
  end
end
