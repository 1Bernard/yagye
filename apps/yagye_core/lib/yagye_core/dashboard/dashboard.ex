defmodule YagyeCore.Dashboard do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Ledger.Schemas.{Account, Balance}
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.{MerchantSettlementControls, SettlementBatch}

  # ── Ops KPIs ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the ops settlement operations summary:
  - `float_balances`: provider float (settlement_pending) per provider, currency, and mode
  - `merchant_payables`: what Yagye currently owes each merchant, by currency and mode
  - `pipeline`: settlement batch counts by state
  - `failed_disbursements`: most recent 50 failed / rejected batches
  """
  def ops_summary do
    %{
      float_balances: provider_float_balances(),
      merchant_payables: merchant_payable_balances(),
      pipeline: settlement_pipeline(),
      failed_disbursements: failed_disbursements()
    }
  end

  # ── Merchant KPIs ────────────────────────────────────────────────────────────

  @doc """
  Returns the merchant's settlement summary:
  - `payable_balances`: what Yagye currently owes this merchant, by currency and mode
  - `destination`: how funds will be disbursed (mobile | bank | none)
  - `recent_batches`: last 10 batches with human-readable state labels
  """
  def merchant_settlement_summary(merchant_id) do
    %{
      payable_balances: merchant_payable_balance(merchant_id),
      destination: settlement_destination(merchant_id),
      recent_batches: recent_batches(merchant_id)
    }
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp provider_float_balances do
    from(a in Account,
      join: b in Balance,
      on: b.account_id == a.id,
      join: p in Provider,
      on: p.id == a.scope_id,
      where: a.account_type == "settlement_pending" and a.scope_type == "provider",
      select: %{
        provider_code: p.code,
        provider_name: p.display_name,
        currency: a.currency,
        mode: a.mode,
        balance: b.balance
      },
      order_by: [asc: p.code, asc: a.currency, asc: a.mode]
    )
    |> Repo.all()
  end

  defp settlement_pipeline do
    from(b in SettlementBatch,
      group_by: b.state,
      select: {b.state, count(b.id)}
    )
    |> Repo.all()
    |> Enum.into(%{}, fn {state, count} -> {state, count} end)
  end

  defp failed_disbursements do
    from(b in SettlementBatch,
      where: b.state in ["failed", "dispatch_rejected"],
      order_by: [desc: b.inserted_at],
      limit: 50,
      select: %{
        id: b.id,
        merchant_id: b.merchant_id,
        provider_id: b.provider_id,
        state: b.state,
        currency: b.currency,
        gross_amount: b.gross_amount,
        mode: b.mode,
        inserted_at: b.inserted_at
      }
    )
    |> Repo.all()
  end

  # What Yagye owes all merchants — join merchant_payable accounts with merchant names.
  # Excludes zero balances (nothing pending). Sorted by balance descending so the
  # largest outstanding amounts surface first for ops prioritisation.
  defp merchant_payable_balances do
    from(a in Account,
      join: b in Balance,
      on: b.account_id == a.id,
      join: m in Merchant,
      on: m.id == a.scope_id,
      where:
        a.account_type == "merchant_payable" and
          a.scope_type == "merchant" and
          b.balance > 0,
      select: %{
        merchant_id: m.public_id,
        merchant_name: m.trading_name,
        currency: a.currency,
        mode: a.mode,
        balance: b.balance
      },
      order_by: [desc: b.balance]
    )
    |> Repo.all()
  end

  # What Yagye owes a specific merchant across all currencies and modes.
  defp merchant_payable_balance(merchant_id) do
    from(a in Account,
      join: b in Balance,
      on: b.account_id == a.id,
      where:
        a.account_type == "merchant_payable" and
          a.scope_type == "merchant" and
          a.scope_id == ^merchant_id and
          b.balance > 0,
      select: %{
        currency: a.currency,
        mode: a.mode,
        balance: b.balance
      },
      order_by: [asc: a.currency, asc: a.mode]
    )
    |> Repo.all()
  end

  defp settlement_destination(merchant_id) do
    case Repo.get_by(MerchantSettlementControls, merchant_id: merchant_id) do
      nil ->
        %{type: "none"}

      %{settlement_msisdn: msisdn} when is_binary(msisdn) and msisdn != "" ->
        %{type: "mobile_wallet", msisdn: msisdn}

      %{
        settlement_bank_code: code,
        settlement_account_number: acct,
        settlement_account_name: name
      }
      when is_binary(code) and is_binary(acct) ->
        %{type: "bank_account", bank_code: code, account_number: acct, account_name: name}

      _ ->
        %{type: "none"}
    end
  end

  defp recent_batches(merchant_id) do
    from(b in SettlementBatch,
      where: b.merchant_id == ^merchant_id,
      order_by: [desc: b.inserted_at],
      limit: 10,
      select: %{
        id: b.id,
        state: b.state,
        state_label: b.state,
        currency: b.currency,
        gross_amount: b.gross_amount,
        mode: b.mode,
        bank_dispatch_ref: b.bank_dispatch_ref,
        inserted_at: b.inserted_at
      }
    )
    |> Repo.all()
    |> Enum.map(&put_state_label/1)
  end

  @state_labels %{
    "pending" => "Pending",
    "processing" => "Processing",
    "settled" => "Settled",
    "awaiting_approval" => "Awaiting Approval",
    "dispatch_rejected" => "Dispatch Rejected",
    "failed" => "Failed"
  }

  defp put_state_label(%{state: state} = batch) do
    Map.put(batch, :state_label, Map.get(@state_labels, state, state))
  end
end
