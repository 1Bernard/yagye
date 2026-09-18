# Invoice seed data — safe to re-run (skips by invoice number).
#
# Usage (from apps/yagye_core):
#   mix run priv/repo/seeds_invoices.exs

alias YagyeCore.Invoices
alias YagyeCore.Invoices.Schemas.Invoice
alias YagyeCore.Merchants.Schemas.Merchant
alias YagyeCore.Repo

IO.puts("\n=== Invoice seeds ===\n")

# ── 1. Look up the dev merchant ──────────────────────────────────────────────

merchant =
  case Repo.get_by(Merchant, legal_name: "Dev Merchant") do
    nil ->
      IO.puts("ERROR: Dev Merchant not found — run seeds.exs first.")
      System.halt(1)

    m ->
      IO.puts("Merchant: #{m.public_id} (#{m.legal_name})")
      m
  end

# ── 2. Invoice definitions ────────────────────────────────────────────────────
# Amounts are in minor units (pesewas for GHS).
# GHS 850.00 = 85_000 pesewas.

today = Date.utc_today()

invoices = [
  %{
    number: "INV-001",
    customer_reference: "Kofi Boateng Supplies",
    state: "paid",
    issue_date: Date.add(today, -45),
    due_date: Date.add(today, -30),
    paid_at: DateTime.add(DateTime.utc_now(), -25 * 86_400),
    notes: "Thank you for your continued business.",
    terms: "Payment within 15 days of invoice date.",
    line_items: [
      %{description: "Mobile Money integration setup", quantity: 1, unit_amount: 500_000, tax_rate_bps: 0},
      %{description: "API access — Q4 (3 months)",    quantity: 3, unit_amount: 150_000, tax_rate_bps: 0}
    ]
  },
  %{
    number: "INV-002",
    customer_reference: "Ama Serwaa Trading Co",
    state: "open",
    issue_date: Date.add(today, -10),
    due_date: Date.add(today, 20),
    notes: nil,
    terms: "Net 30.",
    line_items: [
      %{description: "Payment gateway monthly fee",       quantity: 1, unit_amount: 250_000, tax_rate_bps: 0},
      %{description: "Transaction processing — October",  quantity: 1, unit_amount: 125_000, tax_rate_bps: 1500}
    ]
  },
  %{
    number: "INV-003",
    customer_reference: "Kwame Tech Solutions",
    state: "overdue",
    issue_date: Date.add(today, -60),
    due_date: Date.add(today, -30),
    notes: "Please settle this balance at your earliest convenience.",
    terms: nil,
    line_items: [
      %{description: "Custom checkout page development",      quantity: 1, unit_amount: 1_200_000, tax_rate_bps: 0},
      %{description: "SMS notification bundle (500 credits)", quantity: 2, unit_amount: 80_000,    tax_rate_bps: 0}
    ]
  },
  %{
    number: "INV-004",
    customer_reference: "Kofi Boateng Supplies",
    state: "draft",
    issue_date: today,
    due_date: Date.add(today, 30),
    notes: "Quarterly retainer — please review before we issue.",
    terms: "Payment due within 30 days.",
    line_items: [
      %{description: "Q4 platform retainer",    quantity: 1, unit_amount: 450_000, tax_rate_bps: 0},
      %{description: "Support hours — October", quantity: 8, unit_amount:  75_000, tax_rate_bps: 0},
      %{description: "Infrastructure hosting",  quantity: 1, unit_amount: 180_000, tax_rate_bps: 0}
    ]
  },
  %{
    number: "INV-005",
    customer_reference: "Ama Serwaa Trading Co",
    state: "void",
    issue_date: Date.add(today, -20),
    due_date: Date.add(today, 10),
    voided_at: DateTime.add(DateTime.utc_now(), -5 * 86_400),
    notes: nil,
    terms: nil,
    line_items: [
      %{description: "Duplicate charge — voided", quantity: 1, unit_amount: 250_000, tax_rate_bps: 0}
    ]
  }
]

# ── 3. Insert invoices ────────────────────────────────────────────────────────

Enum.each(invoices, fn attrs ->
  if Repo.get_by(Invoice, number: attrs.number, merchant_id: merchant.id) do
    IO.puts("Invoice #{attrs.number}: already exists — skipping")
  else
    create_attrs =
      attrs
      |> Map.take([:number, :customer_reference, :issue_date, :due_date, :notes, :terms, :line_items])
      |> Map.put(:currency, "GHS")

    {:ok, invoice} = Invoices.create_invoice(merchant.id, create_attrs)

    invoice =
      case attrs.state do
        "draft" ->
          invoice

        "open" ->
          {:ok, i} = Invoices.issue_invoice(invoice.public_id)
          i

        state when state in ~w[paid overdue void] ->
          {:ok, issued} = Invoices.issue_invoice(invoice.public_id)

          extra =
            cond do
              Map.has_key?(attrs, :paid_at) ->
                %{paid_at: attrs.paid_at, amount_paid: issued.total_amount}
              Map.has_key?(attrs, :voided_at) ->
                %{voided_at: attrs.voided_at}
              true ->
                %{}
            end

          {:ok, final} =
            issued
            |> Invoice.state_changeset(state, extra)
            |> Repo.update()

          final
      end

    IO.puts("Invoice #{invoice.number}: created (#{invoice.public_id}) — #{invoice.state}")
  end
end)

IO.puts("\n=== Done ===\n")
