defmodule Simulator.Settlements do
  @moduledoc """
  Generates and stores settlement files for simulator accounts.

  A settlement file is generated once per (account_id, date) — subsequent calls
  return the cached file. Defects from the account's default scenario are injected
  deterministically: missing lines by modulo, fee drift by adjusting the fee bps.
  """

  import Ecto.Query

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Charges.Schemas.Charge
  alias Simulator.Repo
  alias Simulator.Settlements.Schemas.{SettlementFile, SettlementLine}

  @doc """
  Returns the settlement file for `account` on `date`, generating it if needed.

  Applies scenario defects from `account.default_scenario`:
  - `fee_drift_bps` — fee bps are increased by this amount
  - `settlement_missing_line_rate` — fraction of lines omitted deterministically
  """
  def generate_report(%Account{} = account, %Date{} = date) do
    account = preload_scenario(account)

    case get_existing_file(account.id, date) do
      nil -> create_report(account, date)
      file -> {:ok, Repo.preload(file, :lines)}
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp preload_scenario(%Account{default_scenario: %Ecto.Association.NotLoaded{}} = account) do
    Repo.preload(account, :default_scenario)
  end

  defp preload_scenario(account), do: account

  defp get_existing_file(account_id, date) do
    Repo.get_by(SettlementFile, account_id: account_id, settlement_date: date)
  end

  defp create_report(account, date) do
    charges = fetch_settled_charges(account.id, date)
    scenario = account.default_scenario

    lines_params = build_lines(charges, account, scenario, date)

    gross_total = lines_params |> Enum.map(& &1.gross_minor) |> Enum.sum()
    fee_total = lines_params |> Enum.map(& &1.fee_minor) |> Enum.sum()
    net_total = lines_params |> Enum.map(& &1.net_minor) |> Enum.sum()

    defect_tag = detect_defect_tag(scenario)

    Repo.transaction(fn ->
      {:ok, file} =
        %SettlementFile{}
        |> SettlementFile.changeset(%{
          account_id: account.id,
          file_ref: "SF_" <> Uniq.UUID.uuid7(),
          settlement_date: date,
          format: "JSON",
          currency: account.currency,
          gross_minor: gross_total,
          fee_minor: fee_total,
          net_minor: net_total,
          line_count: length(lines_params),
          injected_defect: defect_tag,
          generated_at: DateTime.utc_now()
        })
        |> Repo.insert()

      Enum.each(lines_params, fn params ->
        %SettlementLine{}
        |> SettlementLine.changeset(Map.put(params, :file_id, file.id))
        |> Repo.insert!()
      end)

      Repo.preload(file, :lines)
    end)
  end

  defp fetch_settled_charges(account_id, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    Repo.all(
      from c in Charge,
        where: c.account_id == ^account_id,
        where: c.state in ["AUTHORISED", "CAPTURED"],
        where: c.created_at >= ^start_dt,
        where: c.created_at < ^end_dt,
        order_by: [asc: c.created_at],
        select: %{
          charge_ref: c.charge_ref,
          amount_minor: c.amount_minor,
          created_at: c.created_at
        }
    )
  end

  defp build_lines(charges, account, scenario, date) do
    fee_bps = account.fee_percentage_bps + drift_bps(scenario)
    fee_fixed = account.fee_fixed_minor
    rate = missing_rate(scenario)

    charges
    |> maybe_drop_lines(rate)
    |> Enum.with_index(1)
    |> Enum.map(fn {charge, line_number} ->
      gross = charge.amount_minor
      fee = div(gross * fee_bps, 10_000) + fee_fixed
      net = gross - fee

      %{
        line_number: line_number,
        charge_ref: charge.charge_ref,
        line_type: "CHARGE",
        gross_minor: gross,
        fee_minor: fee,
        net_minor: net,
        value_date: date,
        malformed: false
      }
    end)
  end

  defp maybe_drop_lines(charges, rate) when rate == 0.0, do: charges

  defp maybe_drop_lines(charges, rate) do
    skip_every = round(1.0 / rate)

    charges
    |> Enum.with_index(1)
    |> Enum.reject(fn {_charge, idx} -> rem(idx, skip_every) == 0 end)
    |> Enum.map(fn {charge, _idx} -> charge end)
  end

  defp drift_bps(nil), do: 0
  defp drift_bps(%{fee_drift_bps: bps}) when is_integer(bps), do: bps
  defp drift_bps(_), do: 0

  defp missing_rate(nil), do: 0.0

  defp missing_rate(%{settlement_missing_line_rate: rate}) when not is_nil(rate) do
    Decimal.to_float(rate)
  end

  defp missing_rate(_), do: 0.0

  defp detect_defect_tag(nil), do: nil

  defp detect_defect_tag(scenario) do
    cond do
      Decimal.to_float(scenario.settlement_missing_line_rate || Decimal.new(0)) > 0 ->
        "missing_line"

      (scenario.fee_drift_bps || 0) > 0 ->
        "fee_drift"

      true ->
        nil
    end
  end
end
