defmodule YagyeCore.Projections.Workers.DailyMetricsWorker do
  @moduledoc false

  # Recomputes proj_daily_merchant_metrics from source tables.
  # Runs hourly via Oban cron — does NOT consume outbox events.
  #
  # Recompute-from-source is correct here because daily metrics are volume
  # counters (proportional). A wrong count self-corrects on the next hourly run.
  # Contrast with proj_merchant_balances (money) where a wrong value is a
  # misstatement and must be corrected by event dedup, not recompute.

  use Oban.Worker, queue: :projections, max_attempts: 3

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Projections.Schemas.DailyMetrics
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Accept an explicit date for backfills; default to today
    day =
      case args do
        %{"day" => day_str} -> Date.from_iso8601!(day_str)
        _ -> Date.utc_today()
      end

    recompute_day(day)
    :ok
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp recompute_day(day) do
    rows = aggregate_from_source(day)

    Enum.each(rows, fn row ->
      %DailyMetrics{}
      |> DailyMetrics.changeset(Map.put(row, :day, day))
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:merchant_id, :day, :currency, :mode]},
        conflict_target: [:merchant_id, :day, :currency, :mode]
      )
    end)
  end

  defp aggregate_from_source(day) do
    start_of_day = DateTime.new!(day, ~T[00:00:00], "Etc/UTC")
    end_of_day = DateTime.new!(Date.add(day, 1), ~T[00:00:00], "Etc/UTC")

    from(p in Payment,
      where: p.inserted_at >= ^start_of_day and p.inserted_at < ^end_of_day,
      group_by: [p.merchant_id, p.currency, p.mode],
      select: %{
        merchant_id: p.merchant_id,
        currency: p.currency,
        mode: p.mode,
        payment_count: count(p.id),
        succeeded_count: sum(fragment("CASE WHEN ? = 'succeeded' THEN 1 ELSE 0 END", p.state)),
        failed_count: sum(fragment("CASE WHEN ? = 'failed' THEN 1 ELSE 0 END", p.state)),
        gross_volume:
          sum(fragment("CASE WHEN ? = 'succeeded' THEN ? ELSE 0 END", p.state, p.amount)),
        net_volume:
          sum(fragment("CASE WHEN ? = 'succeeded' THEN ? ELSE 0 END", p.state, p.amount)),
        refund_volume: fragment("0"),
        chargeback_count: fragment("0")
      }
    )
    |> Repo.all()
  end
end
