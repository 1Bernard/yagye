defmodule YagyeCore.Settlement.Workers.SettlementSchedulerWorker do
  @moduledoc false

  # Runs hourly. For each (merchant, provider, currency, mode) combo with unsettled
  # succeeded payments, checks whether the provider's settlement cutoff has passed
  # in the provider's configured timezone. If so, creates a pending batch and
  # enqueues a SettlementProcessorWorker to carry it through.
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
  alias YagyeCore.Settlement.Workers.SettlementProcessorWorker

  @default_cutoff_hour 23
  @default_timezone "Africa/Accra"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    fetch_unsettled_combos()
    |> Enum.each(&maybe_schedule_batch/1)

    :ok
  end

  defp maybe_schedule_batch(%{merchant_id: mid, provider_id: pid, currency: cur, mode: mode}) do
    provider = Repo.get!(Provider, pid)

    if past_cutoff?(provider.settlement_cadence) do
      dispatch_batch(mid, pid, cur, mode)
    end
  end

  defp dispatch_batch(merchant_id, provider_id, currency, mode) do
    case Settlement.create_batch(merchant_id, provider_id, currency, mode) do
      {:ok, batch} ->
        SettlementProcessorWorker.new(%{"settlement_batch_id" => batch.id})
        |> Oban.insert!()

      {:error, reason} when reason in [:batch_already_open, :no_payments] ->
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
