# Bootstrap seed: creates the platform admin merchant and issues a wildcard
# secret API key. Safe to re-run — skips creation if the admin merchant
# already exists. The key is printed once and cannot be retrieved again.
#
# Usage:
#   mix ecto.setup          (runs migrations + seeds together)
#   mix run priv/repo/seeds.exs   (seeds only, after migrations)

alias YagyeCore.Merchants
alias YagyeCore.Merchants.Merchant
alias YagyeCore.Repo

IO.puts("\n=== Yagye bootstrap ===\n")

case Repo.get_by(Merchant, legal_name: "Yagye Admin") do
  %Merchant{} = merchant ->
    IO.puts("Admin merchant already exists: #{merchant.public_id}")
    IO.puts("Cannot reprint the API key — issue a new one via the API.\n")

  nil ->
    {:ok, {merchant, _}} =
      Merchants.create_merchant(%{
        legal_name: "Yagye Admin",
        trading_name: "Yagye",
        country: "GB",
        default_currency: "GBP"
      })

    IO.puts("Created admin merchant : #{merchant.public_id}")

    # approved_by is stored in the event only — passing own id is fine for bootstrap
    {:ok, {merchant, _}} = Merchants.approve(merchant.id, merchant.id)
    IO.puts("Approved              : status=#{merchant.status}")

    {:ok, {api_key, raw_key, _}} =
      Merchants.issue_api_key(merchant.id, %{
        kind: "secret",
        mode: "live",
        scopes: ["*"],
        created_by: merchant.id
      })

    IO.puts("Issued admin key      : #{api_key.public_id}\n")

    IO.puts("""
    ┌──────────────────────────────────────────────────────────────┐
    │  ADMIN API KEY — store this now, it will never appear again  │
    ├──────────────────────────────────────────────────────────────┤
    │  Merchant : #{String.pad_trailing(merchant.public_id, 48)}│
    │  Key      : #{String.pad_trailing(raw_key, 48)}│
    └──────────────────────────────────────────────────────────────┘
    """)
end
