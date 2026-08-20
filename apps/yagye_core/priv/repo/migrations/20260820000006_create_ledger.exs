defmodule YagyeCore.Repo.Migrations.CreateLedger do
  use Ecto.Migration

  def change do
    # ── ledger_accounts (chart of accounts) ───────────────────────────────────
    create table(:ledger_accounts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # Structured: {account_type}:{scope_id}:{currency}:{mode}
      # e.g. "merchant_payable:01J...:GHS:simulation"
      add :code, :text, null: false
      # merchant_payable|settlement_pending|platform_fees_payable|suspense
      add :account_type, :text, null: false
      # debit|credit — which side increases this account
      add :normal_balance, :text, null: false
      # merchant|provider|platform
      add :scope_type, :text, null: false
      # NULL for platform-scoped accounts
      add :scope_id, :uuid
      add :currency, :string, size: 3, null: false
      add :mode, :text, null: false
      add :allows_negative, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec, updated_at: false, inserted_at: :inserted_at)
    end

    create constraint(:ledger_accounts, :valid_normal_balance,
             check: "normal_balance IN ('debit','credit')"
           )

    create constraint(:ledger_accounts, :valid_scope_type,
             check: "scope_type IN ('merchant','provider','platform')"
           )

    create constraint(:ledger_accounts, :valid_mode,
             check: "mode IN ('simulation','sandbox','live')"
           )

    create unique_index(:ledger_accounts, [:code])

    # ── ledger_entries (journal entries — one per business event) ─────────────
    create table(:ledger_entries, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :mode, :text, null: false
      add :currency, :string, size: 3, null: false
      # payment_settled|refund_issued|payout_released|fee_collected
      add :entry_type, :text, null: false
      # payment|refund|payout
      add :source_type, :text, null: false
      add :source_id, :uuid, null: false
      add :description, :text, null: false
      add :correlation_id, :text, null: false
      # Self-referential: corrections are reversing entries, never edits
      add :reverses_entry_id, references(:ledger_entries, type: :uuid)
      # Bitemporal: when the event economically happened vs when it was recorded
      add :effective_at, :utc_datetime_usec, null: false
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false, inserted_at: :inserted_at)
    end

    create constraint(:ledger_entries, :valid_mode,
             check: "mode IN ('simulation','sandbox','live')"
           )

    create unique_index(:ledger_entries, [:public_id])
    # Idempotency: one entry per (source, entry_type) — safe to retry
    create unique_index(:ledger_entries, [:source_type, :source_id, :entry_type])

    # ── ledger_postings (individual debit/credit legs) ────────────────────────
    # Deliberately bigserial, not uuid — dense, ordered, never exposed,
    # and last_posting_id in ledger_balances is a meaningful watermark.
    create table(:ledger_postings, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :entry_id, references(:ledger_entries, type: :uuid, on_delete: :restrict), null: false

      add :account_id, references(:ledger_accounts, type: :uuid, on_delete: :restrict),
        null: false

      # debit|credit; amount is always > 0, direction carries the sign
      add :direction, :text, null: false
      add :amount, :bigint, null: false
      add :currency, :string, size: 3, null: false
      # Denormalised for query speed (merchant balance queries)
      add :merchant_id, :uuid

      timestamps(type: :utc_datetime_usec, updated_at: false, inserted_at: :inserted_at)
    end

    create constraint(:ledger_postings, :valid_direction,
             check: "direction IN ('debit','credit')"
           )

    create constraint(:ledger_postings, :positive_amount, check: "amount > 0")
    create index(:ledger_postings, [:entry_id])
    create index(:ledger_postings, [:account_id])
    create index(:ledger_postings, [:merchant_id])

    # ── ledger_balances (running balance cache per account) ───────────────────
    # balance = SUM of signed postings up to last_posting_id.
    # Debit adds, credit subtracts. Verified nightly.
    # INVARIANT: per entry, SUM(debits) = SUM(credits).
    # TODO: add a DEFERRED constraint trigger before any ledger code runs in prod.
    create table(:ledger_balances, primary_key: false) do
      add :account_id, references(:ledger_accounts, type: :uuid, on_delete: :restrict),
        primary_key: true,
        null: false

      add :balance, :bigint, null: false, default: 0
      # Watermark — the bigserial ID of the last posting applied to this balance
      add :last_posting_id, :bigint, null: false, default: 0
      add :updated_at, :utc_datetime_usec, null: false
    end
  end
end
