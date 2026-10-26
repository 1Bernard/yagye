defmodule YagyeCore.Settlement.Workers.SettlementSchedulerWorker do
  @moduledoc false

  # Runs hourly. For each (merchant, provider, currency, mode) combo with unsettled
  # succeeded payments, checks:
  #   1. Today is a Ghana business day (skips weekends + public holidays).
  #   2. The provider's settlement cutoff has passed in the provider's timezone.
  #   3. The merchant's settlement_frequency allows settlement today (daily/weekly/monthly).
  #   4. The merchant is not on a settlement hold (on_hold flag in controls).
  # If all pass, creates a pending batch and enqueues a SettlementProcessorWorker.
  #
  # settlement_cadence shapes:
  #   %{}                                              → platform default (23:00 Africa/Accra)
  #   %{"cutoff_hour" => 21, "timezone" => "UTC"}      → 21:00 UTC
  #   %{"cutoff_hour" => 23, "timezone" => "Africa/Lagos"} → 23:00 WAT

  use Oban.Worker, queue: :settlement, max_attempts: 3

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.GhanaBusinessDay
  alias YagyeCore.Settlement.Workers.SettlementProcessorWorker

  @default_cutoff_hour 23
  @default_timezone "Africa/Accra"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if GhanaBusinessDay.business_day?() do
      fetch_unsettled_combos()
      |> Enum.each(&maybe_schedule_batch/1)
    end

    :ok
  end

  defp maybe_schedule_batch(%{merchant_id: mid, provider_id: pid, currency: cur, mode: mode}) do
    provider = Repo.get!(Provider, pid)
    controls = Settlement.get_settlement_controls(mid)

    cond do
      on_hold?(controls) -> :skip
      not past_cutoff?(provider.settlement_cadence) -> :skip
      not frequency_day?(controls) -> :skip
      true -> dispatch_batch(mid, pid, cur, mode)
    end
  end

  defp dispatch_batch(merchant_id, provider_id, currency, mode) do
    case Settlement.create_batch(merchant_id, provider_id, currency, mode) do
      {:ok, batch} ->
        SettlementProcessorWorker.new(%{"settlement_batch_id" => batch.id})
        |> Oban.insert!()

      {:error, reason} when reason in [:batch_already_open, :no_payments, :below_minimum] ->
        :skip
    end
  end

  # Distinct (merchant, provider, currency, mode) combos that have at least one
  # unsettled succeeded payment. Uses the partial index payments_unsettled_idx.
  defp fetch_unsettled_combos do
    from(p in Payment,
      join: pa in "payment_attempts",
      on:
        pa.payment_id == p.id and
          pa.state == "succeeded",
      join: prov in Provider,
      on: prov.id == type(pa.provider_id, :binary_id) and prov.active == true,
      where: p.state == "succeeded" and is_nil(p.settlement_batch_id),
      group_by: [p.merchant_id, pa.provider_id, p.currency, p.mode],
      select: %{
        merchant_id: p.merchant_id,
        provider_id: type(pa.provider_id, :binary_id),
        currency: p.currency,
        mode: p.mode
      }
    )
    |> Repo.all()
  end

  defp on_hold?(nil), do: false
  defp on_hold?(%{on_hold: true}), do: true
  defp on_hold?(_), do: false

  defp frequency_day?(nil), do: true
  defp frequency_day?(%{settlement_frequency: "daily"}), do: true

  defp frequency_day?(%{settlement_frequency: "weekly"}) do
    Date.day_of_week(Date.utc_today()) == 1
  end

  defp frequency_day?(%{settlement_frequency: "monthly"}) do
    today = Date.utc_today()
    first = %Date{today | day: 1}

    # Fire on the 1st; if the 1st is a weekend/holiday, advance to the next business day.
    target =
      if GhanaBusinessDay.business_day?(first),
        do: first,
        else: next_business_day(first)

    Date.compare(today, target) == :eq
  end

  defp frequency_day?(_), do: true

  defp next_business_day(%Date{} = date) do
    candidate = Date.add(date, 1)

    if GhanaBusinessDay.business_day?(candidate),
      do: candidate,
      else: next_business_day(candidate)
  end

  # Returns true when the current hour in the provider's timezone is at or past cutoff.
  defp past_cutoff?(%{"cutoff_hour" => h, "timezone" => tz}) when is_integer(h) do
    local_hour =
      DateTime.utc_now()
      |> DateTime.shift_zone!(tz)
      |> Map.fetch!(:hour)

    local_hour >= h
  end

  defp past_cutoff?(_) do
    local_hour =
      DateTime.utc_now()
      |> DateTime.shift_zone!(@default_timezone)
      |> Map.fetch!(:hour)

    local_hour >= @default_cutoff_hour
  end
end
