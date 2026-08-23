defmodule YagyeCore.Reconciliation.SimulatorReport do
  @moduledoc """
  Generates a synthetic settlement report from simulator data in the DB.

  Reads succeeded payment_attempts for a given provider, mode, and date, then
  produces the same payload shape that a real provider's settlement API would
  return. Used in tests and simulation mode.
  """

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Repo

  @fee_bps 200
  @fee_fixed_minor 20

  @spec generate(binary(), String.t(), Date.t()) :: map()
  def generate(provider_id, mode, %Date{} = report_date) do
    attempts = fetch_succeeded_attempts(provider_id, mode, report_date)

    lines =
      attempts
      |> Enum.with_index(1)
      |> Enum.map(fn {attempt, idx} -> build_line(attempt, idx) end)

    currency = detect_currency(lines, "USD")
    total = lines |> Enum.map(& &1.net_amount) |> Enum.sum()

    payload = %{
      provider_id: provider_id,
      mode: mode,
      report_date: report_date,
      source: "api",
      raw_uri: "s3://yagye-simulator/reports/#{Uniq.UUID.uuid7()}.json",
      currency: currency,
      reported_total: total,
      line_count: length(lines),
      lines: lines
    }

    checksum =
      payload
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Map.put(payload, :checksum, checksum)
  end

  defp fetch_succeeded_attempts(provider_id, mode, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    Repo.all(
      from a in PaymentAttempt,
        join: p in Payment,
        on: a.payment_id == p.id,
        where: a.provider_id == ^provider_id,
        where: p.mode == ^mode,
        where: a.state == "succeeded",
        where: a.inserted_at >= ^start_dt,
        where: a.inserted_at < ^end_dt,
        select: %{
          provider_reference: a.provider_reference,
          amount: p.amount,
          currency: p.currency,
          occurred_at: a.inserted_at
        }
    )
  end

  defp build_line(attempt, line_number) do
    gross = attempt.amount
    fee = div(gross * @fee_bps, 10_000) + @fee_fixed_minor
    net = gross - fee

    %{
      line_number: line_number,
      provider_reference: attempt.provider_reference,
      transaction_type: "CHARGE",
      gross_amount: gross,
      fee_amount: fee,
      net_amount: net,
      currency: attempt.currency,
      occurred_at: attempt.occurred_at,
      value_date: DateTime.to_date(attempt.occurred_at),
      raw: %{
        "ref" => attempt.provider_reference,
        "type" => "CHARGE",
        "gross" => gross,
        "fee" => fee,
        "net" => net,
        "ccy" => attempt.currency
      }
    }
  end

  defp detect_currency([%{currency: ccy} | _], _default), do: ccy
  defp detect_currency([], default), do: default
end
