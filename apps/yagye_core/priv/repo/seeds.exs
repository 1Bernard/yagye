# Bootstrap seed — safe to re-run. Skips any record that already exists.
# Keys are printed once at creation time and cannot be retrieved again.
#
# Usage:
#   mix ecto.setup                  (migrations + seeds)
#   mix run priv/repo/seeds.exs     (seeds only, after migrations)

alias YagyeCore.Merchants
alias YagyeCore.Merchants.Schemas.Merchant
alias YagyeCore.Providers.Schemas.Provider
alias YagyeCore.Repo

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

# ── 2. Admin merchant (live mode, platform ops) ────────────────────────────────

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

# ── 3. Dev merchant (simulation mode, for local testing and K6) ───────────────

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

IO.puts("=== Done ===\n")
