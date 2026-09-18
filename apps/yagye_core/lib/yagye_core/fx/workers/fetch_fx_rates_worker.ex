defmodule YagyeCore.FX.Workers.FetchFxRatesWorker do
  @moduledoc false

  # Fetches daily exchange rates from ExchangeRate-API and upserts them into
  # fx_rates. Runs daily at 06:00 Africa/Accra (WAT = UTC+0 in dry season,
  # UTC+0 year-round since Ghana does not observe DST).
  #
  # Set EXCHANGERATE_API_KEY in the environment. If the key is missing or the
  # external call fails the job logs a warning and returns :ok so Oban does not
  # retry indefinitely — stale rates are better than a stuck queue.
  #
  # Pairs fetched: GHS→USD, GHS→EUR, GHS→GBP
  # Each rate expires 26 hours after insertion (a little more than one day so
  # the dashboard still has a valid rate if the next fetch is slightly delayed).

  use Oban.Worker, queue: :projections, max_attempts: 3

  require Logger

  alias YagyeCore.FX

  @pairs [{"GHS", "USD"}, {"GHS", "EUR"}, {"GHS", "GBP"}]
  @source "exchangerate-api"
  @markup_bps 0
  @ttl_hours 26

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    api_key = System.get_env("EXCHANGERATE_API_KEY")

    if is_nil(api_key) do
      Logger.warning("[FetchFxRatesWorker] EXCHANGERATE_API_KEY not set — skipping rate fetch")
      :ok
    else
      fetch_and_store(api_key)
    end
  end

  defp fetch_and_store(api_key) do
    Enum.each(@pairs, fn {base, quote} ->
      case fetch_rate(api_key, base, quote) do
        {:ok, rate} ->
          store_rate(base, quote, rate)

        {:error, reason} ->
          Logger.warning(
            "[FetchFxRatesWorker] Failed to fetch #{base}/#{quote}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  defp fetch_rate(api_key, base, quote) do
    url = "https://v6.exchangerate-api.com/v6/#{api_key}/pair/#{base}/#{quote}"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"result" => "success", "conversion_rate" => rate}}} ->
        {:ok, rate}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_rate(base, quote, rate) do
    now = DateTime.utc_now()

    attrs = %{
      base: base,
      quote: quote,
      rate: Decimal.from_float(rate / 1.0),
      source: @source,
      markup_bps: @markup_bps,
      quoted_at: now,
      expires_at: DateTime.add(now, @ttl_hours * 3600, :second)
    }

    case FX.insert_rate(attrs) do
      {:ok, _} ->
        Logger.info("[FetchFxRatesWorker] Stored #{base}/#{quote} = #{rate}")

      {:error, changeset} ->
        Logger.warning(
          "[FetchFxRatesWorker] Failed to store #{base}/#{quote}: #{inspect(changeset.errors)}"
        )
    end
  end
end
