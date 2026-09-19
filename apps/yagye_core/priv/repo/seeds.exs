# Bootstrap seed — safe to re-run. Skips any record that already exists.
# Keys are printed once at creation time and cannot be retrieved again.
#
# Usage:
#   mix ecto.setup                  (migrations + seeds)
#   mix run priv/repo/seeds.exs     (seeds only, after migrations)

alias YagyeCore.Merchants
alias YagyeCore.Merchants.Schemas.Merchant
alias YagyeCore.Providers.Schemas.{Provider, ProviderCredential}
alias YagyeCore.Shared.Vault
alias YagyeCore.Customers
alias YagyeCore.Invoices
alias YagyeCore.Repo
import Ecto.Query, only: [from: 2]

IO.puts("\n=== Yagye bootstrap ===\n")

# ── 1. Simulator provider ──────────────────────────────────────────────────────

case Repo.get_by(Provider, code: "simulator") do
  %Provider{} = p ->
    IO.puts("Simulator provider    : already exists (#{p.id})")

  nil ->
    {:ok, p} =
      %Provider{}
      |> Provider.changeset(%{
        code: "simulator",
        display_name: "Gateway Simulator",
        adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
        active: true
      })
      |> Repo.insert()

    IO.puts("Simulator provider    : created (#{p.id})")
end

# ── 2. Simulator platform credential ──────────────────────────────────────────

simulator = Repo.get_by!(Provider, code: "simulator")

case Repo.get_by(ProviderCredential, provider_id: simulator.id, mode: "simulation") do
  %ProviderCredential{} = c ->
    IO.puts("Simulator credential  : already exists (#{c.id})")

  nil ->
    payload =
      Vault.encrypt_map(%{
        "api_key" => "sim_dev_key",
        "webhook_secret" => "sim_webhook_secret_dev"
      })

    {:ok, c} =
      %ProviderCredential{}
      |> ProviderCredential.changeset(%{
        provider_id: simulator.id,
        merchant_id: nil,
        mode: "simulation",
        base_url: "http://localhost:4100",
        encrypted_payload: payload,
        active: true
      })
      |> Repo.insert()

    IO.puts("Simulator credential  : created (#{c.id})")
end

# ── 4. Admin merchant (live mode, platform ops) ────────────────────────────────

case Repo.get_by(Merchant, legal_name: "Yagye Admin") do
  %Merchant{} = m ->
    IO.puts("Admin merchant        : already exists (#{m.public_id})")
    IO.puts("                        Cannot reprint key — issue a new one via the API.")

  nil ->
    {:ok, {m, _}} =
      Merchants.create_merchant(%{
        legal_name: "Yagye Admin",
        trading_name: "Yagye",
        country: "GB",
        default_currency: "GBP"
      })

    {:ok, {m, _}} = Merchants.approve(m.public_id, m.id)

    {:ok, {key, raw_key, _}} =
      Merchants.issue_api_key(m.public_id, %{
        kind: "secret",
        mode: "live",
        scopes: ["*"],
        created_by: m.id
      })

    IO.puts("Admin merchant        : created (#{m.public_id})")
    IO.puts("Issued admin key      : #{key.public_id}")

    IO.puts("""

    ┌──────────────────────────────────────────────────────────────┐
    │  ADMIN API KEY — store this now, it will never appear again  │
    ├──────────────────────────────────────────────────────────────┤
    │  Merchant : #{String.pad_trailing(m.public_id, 48)}│
    │  Key      : #{String.pad_trailing(raw_key, 48)}│
    └──────────────────────────────────────────────────────────────┘
    """)
end

# ── 5. Dev merchant (simulation mode, for local testing and K6) ───────────────

case Repo.get_by(Merchant, legal_name: "Dev Merchant") do
  %Merchant{} = m ->
    IO.puts("Dev merchant          : already exists (#{m.public_id})")
    IO.puts("                        Cannot reprint keys — issue new ones via the API.")

  nil ->
    {:ok, {m, _}} =
      Merchants.create_merchant(%{
        legal_name: "Dev Merchant",
        trading_name: "Dev Co",
        country: "GH",
        default_currency: "GHS"
      })

    {:ok, {m, _}} = Merchants.approve(m.public_id, m.id)

    {:ok, {sk, raw_sk, _}} =
      Merchants.issue_api_key(m.public_id, %{
        kind: "secret",
        mode: "simulation",
        scopes: ["*"],
        created_by: m.id
      })

    {:ok, {pk, raw_pk, _}} =
      Merchants.issue_api_key(m.public_id, %{
        kind: "publishable",
        mode: "simulation",
        scopes: ["payments:write"],
        created_by: m.id
      })

    IO.puts("Dev merchant          : created (#{m.public_id})")
    IO.puts("Issued secret key     : #{sk.public_id}")
    IO.puts("Issued publishable key: #{pk.public_id}")

    IO.puts("""

    ┌──────────────────────────────────────────────────────────────────┐
    │  DEV API KEYS — store these now, they will never appear again    │
    ├──────────────────────────────────────────────────────────────────┤
    │  Merchant    : #{String.pad_trailing(m.public_id, 50)}│
    │  Secret key  : #{String.pad_trailing(raw_sk, 50)}│
    │  Publishable : #{String.pad_trailing(raw_pk, 50)}│
    └──────────────────────────────────────────────────────────────────┘
    """)
end

# ── 6. External PSP providers (Model B — no platform credentials) ─────────────
# These providers are used when enterprise merchants bring their own PSP accounts.
# Credentials are merchant-level (provider_credentials.merchant_id IS NOT NULL).
# Platform-level credentials are NOT seeded — Yagye does not hold Flutterwave
# or Paystack API keys on behalf of all merchants.

[
  %{
    code: "flutterwave",
    display_name: "Flutterwave",
    adapter_module: "YagyeCore.Payments.Adapters.FlutterwaveAdapter",
    kind: "external_psp",
    capabilities: %{"mobile_money_gh" => true, "card" => false}
  },
  %{
    code: "paystack",
    display_name: "Paystack",
    adapter_module: "YagyeCore.Payments.Adapters.PaystackAdapter",
    kind: "external_psp",
    capabilities: %{"mobile_money_gh" => true, "card" => false}
  }
]
|> Enum.each(fn attrs ->
  case Repo.get_by(Provider, code: attrs.code) do
    %Provider{} = p ->
      IO.puts("#{String.pad_trailing(attrs.display_name, 22)}: already exists (#{p.id})")

    nil ->
      {:ok, p} = %Provider{} |> Provider.changeset(attrs) |> Repo.insert()
      IO.puts("#{String.pad_trailing(attrs.display_name, 22)}: created (#{p.id})")
  end
end)

# ── 7. Portal demo merchant (MCH_DEMO_001 — "Kofi Builds Ltd") ────────────────
# This public_id matches the portal's DEMO_MERCHANT_CODE so the demo merchant
# user (owner@kofibuilds.com) can see invoices and payment links via the API.

demo_merchant =
  case Repo.get_by(Merchant, public_id: "MCH_DEMO_001") do
    %Merchant{} = m ->
      IO.puts("Demo merchant         : already exists (MCH_DEMO_001)")
      m

    nil ->
      {:ok, m} =
        %Merchant{}
        |> Merchant.changeset(%{
          public_id: "MCH_DEMO_001",
          legal_name: "Kofi Builds Ltd",
          trading_name: "Kofi Builds",
          country: "GH",
          default_currency: "GHS",
          status: "approved",
          onboarding_state: "approved",
          kyb_tier: 1,
          api_version: "2025-01-01"
        })
        |> Repo.insert()

      IO.puts("Demo merchant         : created (MCH_DEMO_001)")
      m
  end

# ── 8. Demo invoices for MCH_DEMO_001 ─────────────────────────────────────────

demo_invoice_count =
  Repo.aggregate(
    from(i in YagyeCore.Invoices.Schemas.Invoice, where: i.merchant_id == ^demo_merchant.id),
    :count
  )

if demo_invoice_count < 4 do
  # Seed customers first
  {:ok, acme} = Customers.find_or_create(demo_merchant.id, "acme@globaltrading.com", %{})
  {:ok, nana} = Customers.find_or_create(demo_merchant.id, "nana@buildersgh.com", %{})
  {:ok, sefa} = Customers.find_or_create(demo_merchant.id, "sefa@techstartup.io", %{})

  demo_invoices = [
    %{
      customer_id: nana.id,
      number: "INV-00041",
      currency: "GHS",
      issue_date: ~D[2026-08-01],
      due_date: ~D[2026-08-31],
      mode: "simulation",
      notes: "Thank you for your continued partnership.",
      terms: "Payment due within 30 days.",
      line_items: [
        %{
          description: "Web App Development — Phase 1",
          quantity: 1.0,
          unit_amount: 350_000,
          tax_rate_bps: 0
        },
        %{
          description: "UI/UX Design & Prototyping",
          quantity: 1.0,
          unit_amount: 120_000,
          tax_rate_bps: 0
        }
      ]
    },
    %{
      customer_id: acme.id,
      number: "INV-00040",
      currency: "GHS",
      issue_date: ~D[2026-07-15],
      due_date: ~D[2026-08-14],
      mode: "simulation",
      notes: "Please reference invoice number on your bank transfer.",
      terms: "Net 30.",
      line_items: [
        %{
          description: "Monthly retainer — July 2026",
          quantity: 1.0,
          unit_amount: 500_000,
          tax_rate_bps: 0
        },
        %{
          description: "Additional consulting (8 hrs)",
          quantity: 8.0,
          unit_amount: 25_000,
          tax_rate_bps: 0
        }
      ]
    },
    %{
      customer_id: sefa.id,
      number: "INV-00039",
      currency: "GHS",
      issue_date: ~D[2026-07-01],
      due_date: ~D[2026-07-31],
      mode: "simulation",
      line_items: [
        %{
          description: "API integration — payment gateway",
          quantity: 1.0,
          unit_amount: 200_000,
          tax_rate_bps: 0
        },
        %{
          description: "Technical documentation",
          quantity: 1.0,
          unit_amount: 50_000,
          tax_rate_bps: 0
        },
        %{
          description: "Hosting setup & configuration",
          quantity: 1.0,
          unit_amount: 30_000,
          tax_rate_bps: 0
        }
      ]
    },
    %{
      customer_id: acme.id,
      number: "INV-00038",
      currency: "GHS",
      issue_date: ~D[2026-06-15],
      due_date: ~D[2026-07-15],
      mode: "simulation",
      notes: "Thank you for choosing Kofi Builds.",
      line_items: [
        %{
          description: "Monthly retainer — June 2026",
          quantity: 1.0,
          unit_amount: 500_000,
          tax_rate_bps: 0
        }
      ]
    }
  ]

  Enum.each(demo_invoices, fn attrs ->
    {:ok, _invoice} = Invoices.create_invoice(demo_merchant.id, attrs)
  end)

  IO.puts("Demo invoices         : seeded #{length(demo_invoices)} invoices for MCH_DEMO_001")
else
  IO.puts("Demo invoices         : already seeded (#{demo_invoice_count} records) — skipping")
end

IO.puts("=== Done ===\n")
