defmodule YagyeCore.Shared.BusinessCalendar do
  @moduledoc false

  # Ghana Public Holidays Act fixed-date holidays.
  # Variable-date holidays — Good Friday, Easter Monday, Eid al-Fitr, Eid al-Adha,
  # Founders Day (first Monday August), Kwame Nkrumah Memorial (first Monday September),
  # Farmers Day (first Friday December) — are NOT included here because they shift year
  # to year. Ops should set merchant_settlement_controls.on_hold for those dates when
  # the Government of Ghana publishes the annual holiday gazette.
  @ghana_fixed_holidays [
    {1, 1},
    {1, 7},
    {3, 6},
    {5, 1},
    {5, 25},
    {7, 1},
    {12, 25},
    {12, 26}
  ]

  @doc "Returns true when `date` is a Ghana working day (not a weekend, not a fixed public holiday)."
  @spec business_day?(Date.t()) :: boolean()
  def business_day?(%Date{} = date) do
    not weekend?(date) and not ghana_fixed_holiday?(date)
  end

  @doc "Returns true when today in `timezone` is a Ghana working day."
  @spec today_business_day?(String.t()) :: boolean()
  def today_business_day?(timezone \\ "Africa/Accra") do
    today =
      DateTime.utc_now()
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()

    business_day?(today)
  end

  @doc """
  Returns the UTC datetime cutoff for T+N settlement eligibility.

  Payments inserted_at <= cutoff are eligible for the current settlement run.
  Example: delay_days=1 → only payments from before yesterday's cutoff_hour.
  """
  @spec settlement_cutoff_datetime(pos_integer(), non_neg_integer(), String.t()) :: DateTime.t()
  def settlement_cutoff_datetime(delay_days, cutoff_hour \\ 23, timezone \\ "Africa/Accra")
      when delay_days >= 1 do
    today =
      DateTime.utc_now()
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()

    target_date = business_days_ago(today, delay_days)

    {:ok, naive} = NaiveDateTime.new(target_date, Time.new!(cutoff_hour, 0, 0, 0))
    DateTime.from_naive!(naive, timezone) |> DateTime.shift_zone!("UTC")
  end

  defp business_days_ago(%Date{} = date, 0), do: date

  defp business_days_ago(%Date{} = date, n) do
    prev = Date.add(date, -1)
    if business_day?(prev), do: business_days_ago(prev, n - 1), else: business_days_ago(prev, n)
  end

  defp weekend?(%Date{} = d), do: Date.day_of_week(d) in [6, 7]

  defp ghana_fixed_holiday?(%Date{} = d), do: {d.month, d.day} in @ghana_fixed_holidays
end
