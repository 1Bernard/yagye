defmodule YagyeCore.Ledger do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Ledger.Schemas.{Account, Balance, Entry, Posting}
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  # Posts the "payment_settled" journal entry when a payment succeeds.
  # Must be called within the handle_provider_response transaction so the
  # ledger write and the payment state change are atomic.
  #
  # Accounts created on demand (idempotent via ON CONFLICT DO NOTHING).
  # Balance updated via INSERT ... ON CONFLICT DO UPDATE — atomic, no race.
  #
  # Debit  : settlement_pending — we are owed funds from the provider (asset ↑)
  # Credit : merchant_payable   — we owe the merchant net funds (liability ↑)
  #
  # Fee split is deferred to P8 (requires pricing_rules).
  def post_payment_settled(%Payment{} = payment, %PaymentAttempt{} = attempt) do
    with {:ok, settlement_account} <-
           get_or_create_account(%{
             account_type: "settlement_pending",
             normal_balance: "debit",
             scope_type: "provider",
             scope_id: attempt.provider_id,
             currency: payment.currency,
             mode: payment.mode,
             allows_negative: false
           }),
         {:ok, merchant_account} <-
           get_or_create_account(%{
             account_type: "merchant_payable",
             normal_balance: "credit",
             scope_type: "merchant",
             scope_id: payment.merchant_id,
             currency: payment.currency,
             mode: payment.mode,
             allows_negative: false
           }),
         {:ok, entry} <- insert_entry(payment),
         {:ok, debit} <-
           insert_posting(entry, settlement_account, "debit", payment.amount, payment.merchant_id),
         {:ok, credit} <-
           insert_posting(entry, merchant_account, "credit", payment.amount, payment.merchant_id) do
      apply_balance(settlement_account.id, payment.amount, :debit, debit.id)
      apply_balance(merchant_account.id, payment.amount, :credit, credit.id)
      {:ok, entry}
    end
  end

  def get_balance(account_id) do
    case Repo.get(Balance, account_id) do
      nil -> {:ok, 0}
      bal -> {:ok, bal.balance}
    end
  end

  def get_account(code) do
    case Repo.get_by(Account, code: code) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp get_or_create_account(attrs) do
    code = build_account_code(attrs)
    attrs = Map.put(attrs, :code, code)

    # Uniq.UUID generates IDs client-side, so the returned struct always has a
    # non-nil id even when ON CONFLICT DO NOTHING skips the insert. We can't use
    # {:ok, %Account{id: nil}} to detect conflicts — always fetch from DB instead.
    case Repo.insert(Account.changeset(%Account{}, attrs),
           on_conflict: :nothing,
           conflict_target: :code
         ) do
      {:ok, _} ->
        {:ok, Repo.get_by!(Account, code: code)}

      {:error, _} = err ->
        err
    end
  end

  defp insert_entry(%Payment{} = payment) do
    now = DateTime.utc_now()

    Entry.changeset(%Entry{}, %{
      mode: payment.mode,
      currency: payment.currency,
      entry_type: "payment_settled",
      source_type: "payment",
      source_id: payment.id,
      description: "Payment settled: #{payment.public_id}",
      correlation_id: payment.public_id,
      effective_at: now,
      recorded_at: now
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :entry_type]
    )
    |> case do
      {:ok, _} ->
        # Fetch from DB — Uniq.UUID generates IDs client-side so id: nil detection
        # is unreliable when ON CONFLICT DO NOTHING skips the insert.
        {:ok,
         Repo.get_by!(Entry,
           source_type: "payment",
           source_id: payment.id,
           entry_type: "payment_settled"
         )}

      {:error, _} = err ->
        err
    end
  end

  defp insert_posting(%Entry{} = entry, %Account{} = account, direction, amount, merchant_id) do
    Posting.changeset(%Posting{}, %{
      entry_id: entry.id,
      account_id: account.id,
      direction: direction,
      amount: amount,
      currency: account.currency,
      merchant_id: merchant_id
    })
    |> Repo.insert()
  end

  # SELECT FOR UPDATE locks the balance row before applying the delta.
  # This prevents concurrent payments for the same account from producing incorrect balances.
  # If no balance row exists yet, INSERT the first one.
  defp apply_balance(account_id, amount, direction, posting_id) do
    delta = if direction == :debit, do: amount, else: -amount
    now = DateTime.utc_now()

    existing =
      from(b in "ledger_balances",
        where: b.account_id == type(^account_id, :binary_id),
        lock: "FOR UPDATE",
        select: b.balance
      )
      |> Repo.one()

    case existing do
      nil ->
        Repo.insert_all("ledger_balances", [
          %{
            account_id: Ecto.UUID.dump!(account_id),
            balance: delta,
            last_posting_id: posting_id,
            updated_at: now
          }
        ])

      _ ->
        Repo.update_all(
          from(b in "ledger_balances",
            where: b.account_id == type(^account_id, :binary_id)
          ),
          inc: [balance: delta],
          set: [last_posting_id: posting_id, updated_at: now]
        )
    end
  end

  defp build_account_code(%{account_type: type, scope_id: nil, currency: currency, mode: mode}) do
    "#{type}:platform:#{currency}:#{mode}"
  end

  defp build_account_code(%{
         account_type: type,
         scope_id: scope_id,
         currency: currency,
         mode: mode
       }) do
    "#{type}:#{scope_id}:#{currency}:#{mode}"
  end
end
