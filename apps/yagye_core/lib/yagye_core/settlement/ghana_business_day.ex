defmodule YagyeCore.Settlement.GhanaBusinessDay do
  @moduledoc """
  Ghana business day utilities for settlement scheduling.

  Weekends (Sat/Sun) and Ghana public holidays are non-business days.
  Fixed holidays: New Year's Day, Independence Day, Workers' Day,
  Founders' Day, Christmas Day, Boxing Day.
  Moveable holidays: Good Friday, Easter Monday, National Farmers' Day
  (first Friday of December).

  ## Easter date maintenance

  Good Friday and Easter Monday are pre-computed rather than calculated at
  runtime because the Gregorian computus algorithm is non-trivial and
  error-prone to implement correctly. The list currently covers 2025–2031.

  **Before production runs in 2032**, append the Good Friday and Easter Monday
  dates for 2032 onwards to `@moveable_holidays`. Ghana Public Holidays are
  announced years in advance, so dates for the next 5–10 years are always
  available from the Ghana Tourism Authority or Wikipedia's "Computus" article.

  A compile-time warning fires from 2030 onwards as a reminder.
  """

  @fixed_holidays [
    # New Year's Day
    {1, 1},
    # Independence Day
    {3, 6},
    # Workers' Day
    {5, 1},
    # Founders' Day
    {7, 1},
    # Christmas Day
    {12, 25},
    # Boxing Day
    {12, 26}
  ]

  # Good Friday and Easter Monday pre-computed for 2025–2031.
  # Extend this list before production reaches 2032 — see @moduledoc.
  @moveable_holidays [
    ~D[2025-04-18],
    ~D[2025-04-21],
    ~D[2026-04-03],
    ~D[2026-04-06],
    ~D[2027-03-26],
    ~D[2027-03-29],
    ~D[2028-04-14],
    ~D[2028-04-17],
    ~D[2029-03-30],
    ~D[2029-04-02],
    ~D[2030-04-19],
    ~D[2030-04-22],
    ~D[2031-04-11],
    ~D[2031-04-14]
  ]

  # Warn at compile time when the Easter list is within 2 years of expiry.
  if Date.utc_today().year >= 2030 do
    IO.warn(
      "GhanaBusinessDay: @moveable_holidays only covers Easter dates through 2031. " <>
        "Extend the list to cover 2032+ before the next production deployment.",
      []
    )
  end

  @doc "Returns true if today (UTC) is a Ghana business day."
  def business_day?, do: business_day?(Date.utc_today())

  @doc "Returns true if the given date is a Ghana business day."
  def business_day?(%Date{} = date) do
    Date.day_of_week(date) in 1..5 and not holiday?(date)
  end

  @doc """
  Returns a UTC datetime cutoff for T+N settlement eligibility.
  Payments inserted before this datetime are eligible to be swept.
  """
  def settlement_cutoff_datetime(delay_days) when delay_days >= 1 do
    today = Date.utc_today()
    cutoff_date = subtract_business_days(today, delay_days)

    case DateTime.new(cutoff_date, ~T[23:59:59], "Africa/Accra") do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:gap, _, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:ambiguous, dt, _} -> DateTime.shift_zone!(dt, "Etc/UTC")
    end
  end

  defp holiday?(%Date{month: month, day: day} = date) do
    {month, day} in @fixed_holidays or
      date in @moveable_holidays or
      national_farmers_day?(date)
  end

  # First Friday of December.
  defp national_farmers_day?(%Date{month: 12} = date) do
    Date.day_of_week(date) == 5 and date.day <= 7
  end

  defp national_farmers_day?(_), do: false

  defp subtract_business_days(date, 0), do: date

  defp subtract_business_days(date, n) when n > 0 do
    prev = Date.add(date, -1)

    if business_day?(prev),
      do: subtract_business_days(prev, n - 1),
      else: subtract_business_days(prev, n)
  end
end
