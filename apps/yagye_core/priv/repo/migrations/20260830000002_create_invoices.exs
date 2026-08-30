defmodule YagyeCore.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    # ── invoices ───────────────────────────────────────────────────────────────
    # A commercial obligation — owns the customer-facing view of what is owed.
    # Does not know about ledger postings or provider fees.
    create table(:invoices, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :public_id, :text, null: false
      add :merchant_id, references(:merchants, type: :uuid, on_delete: :restrict), null: false
      add :mode, :text, null: false
      add :customer_id, references(:customers, type: :uuid, on_delete: :restrict), null: false
      # merchant-facing sequence e.g. INV-00123; gapless per merchant per year
      add :number, :text, null: false
      # draft|open|partially_paid|paid|void|uncollectible|overdue
      add :state, :text, null: false, default: "draft"
      add :subtotal_amount, :bigint, null: false
      add :tax_amount, :bigint, null: false
      add :discount_amount, :bigint, null: false
      add :total_amount, :bigint, null: false
      add :amount_paid, :bigint, null: false, default: 0
      add :amount_due, :bigint, null: false
      add :currency, :string, size: 3, null: false
      add :issue_date, :date, null: false
      add :due_date, :date, null: false
      # nullable: linked after payment link is created
      add :payment_link_id, :uuid
      add :notes, :text
      add :terms, :text
      add :sent_at, :utc_datetime_usec
      add :paid_at, :utc_datetime_usec
      # an issued invoice is voided, never deleted
      add :voided_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :inserted_at)
    end

    create constraint(:invoices, :valid_mode, check: "mode IN ('simulation','sandbox','live')")

    create constraint(:invoices, :valid_state,
             check:
               "state IN ('draft','open','partially_paid','paid','void','uncollectible','overdue')"
           )

    create constraint(:invoices, :non_negative_amounts,
             check:
               "subtotal_amount >= 0 AND tax_amount >= 0 AND discount_amount >= 0 AND total_amount >= 0 AND amount_paid >= 0 AND amount_due >= 0"
           )

    create unique_index(:invoices, [:public_id])
    # gapless number is a legal requirement in many jurisdictions
    create unique_index(:invoices, [:merchant_id, :number])

    # ── invoice_line_items ─────────────────────────────────────────────────────
    # INVARIANT: SUM(line items after tax/discount) = invoices.total_amount
    create table(:invoice_line_items, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :invoice_id, references(:invoices, type: :uuid, on_delete: :delete_all), null: false
      # display order
      add :position, :integer, null: false
      add :description, :text, null: false
      # numeric(12,4) allows fractional quantities
      add :quantity, :decimal, precision: 12, scale: 4, null: false
      # currency inherited from parent invoice
      add :unit_amount, :bigint, null: false
      add :tax_rate_bps, :integer, null: false
      add :total_amount, :bigint, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false, inserted_at: :inserted_at)
    end

    create constraint(:invoice_line_items, :positive_quantity, check: "quantity > 0")
    create constraint(:invoice_line_items, :non_negative_tax_rate, check: "tax_rate_bps >= 0")
    create unique_index(:invoice_line_items, [:invoice_id, :position])

    # ── invoice_deliveries ─────────────────────────────────────────────────────
    # Tracks delivery of invoice to customer across channels.
    # destination_hash is a PII-safe hashed value.
    create table(:invoice_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :invoice_id, references(:invoices, type: :uuid, on_delete: :delete_all), null: false
      # email|whatsapp|sms|link_copied
      add :channel, :text, null: false
      # hashed PII (email/phone)
      add :destination_hash, :text, null: false
      # queued|sent|delivered|opened|failed
      add :state, :text, null: false, default: "queued"
      add :provider_reference, :text
      add :sent_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :opened_at, :utc_datetime_usec
      add :failure_reason, :text

      timestamps(type: :utc_datetime_usec, updated_at: false, inserted_at: :inserted_at)
    end

    create constraint(:invoice_deliveries, :valid_channel,
             check: "channel IN ('email','whatsapp','sms','link_copied')"
           )

    create constraint(:invoice_deliveries, :valid_state,
             check: "state IN ('queued','sent','delivered','opened','failed')"
           )

    create index(:invoice_deliveries, [:invoice_id])
  end
end
