defmodule Simulator.BankStatements do
  @moduledoc """
  Generates synthetic bank statement data for the sandbox environment.

  A bank statement represents Yagye's own bank account (e.g. GCB, Ecobank).
  Each day, the MNOs settle their net amounts into that account — one credit
  line per provider. This module aggregates the existing gw_settlement_files
  for a given date across all MNO accounts to produce a matching bank statement.

  Generated on-the-fly — no additional storage needed because the source data
  (gw_settlement_files) is already idempotent.
  """

  import Ecto.Query

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Repo
  alias Simulator.Settlements.Schemas.SettlementFile

  # Seeded opening balance: GHS 500,000.00 — consistent reference point for testing
  @opening_balance_minor 50_000_000

  # GHS 25.00 bank service charge injected for realism
  @bank_charge_minor -2_500
  @bank_charge_narrative "BANK SERVICE CHARGE"

  # Only these MNO accounts produce settlement credits in Yagye's bank account.
  # acct_yagye_platform is the orchestration account and does not settle independently.
  @mno_account_refs ~w[acct_mtn_momo_gh acct_telecel_cash_gh acct_airteltigo_money_gh]

  @narrative_prefix %{
    "acct_mtn_momo_gh" => "MTN MOMO SETTLEMENT",
    "acct_telecel_cash_gh" => "TELECEL CASH SETTLEMENT",
    "acct_airteltigo_money_gh" => "AIRTELTIGO MONEY SETTLEMENT"
  }

  @doc """
  Returns synthetic bank statement data for `date`.

  Result map:
    %{
      statement_date:        Date.t(),
      currency:              "GHS",
      opening_balance_minor: integer(),
      closing_balance_minor: integer(),
      lines: [
        %{value_date: Date.t(), narrative: String.t(), amount_minor: integer()}
      ]
    }
  """
  def generate_statement(%Date{} = date) do
    files = fetch_settlement_files(date)

    credit_lines =
      Enum.map(files, fn file ->
        %{
          value_date: date,
          narrative: build_narrative(file),
          amount_minor: file.net_minor
        }
      end)

    bank_charge = %{
      value_date: date,
      narrative: @bank_charge_narrative,
      amount_minor: @bank_charge_minor
    }

    lines = credit_lines ++ [bank_charge]
    net = Enum.reduce(lines, 0, fn l, acc -> acc + l.amount_minor end)

    {:ok,
     %{
       statement_date: date,
       currency: "GHS",
       opening_balance_minor: @opening_balance_minor,
       closing_balance_minor: @opening_balance_minor + net,
       lines: lines
     }}
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp fetch_settlement_files(date) do
    mno_refs = @mno_account_refs

    Repo.all(
      from f in SettlementFile,
        join: a in Account,
        on: f.account_id == a.id,
        where: f.settlement_date == ^date,
        where: f.net_minor > 0,
        where: a.account_ref in ^mno_refs,
        order_by: [asc: f.generated_at],
        preload: [account: a]
    )
  end

  defp build_narrative(%SettlementFile{} = file) do
    prefix =
      Map.get(@narrative_prefix, file.account.account_ref) ||
        String.upcase(file.account.display_name)

    "#{prefix} REF:#{file.file_ref}"
  end
end
